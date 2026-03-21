--[[
https://source.android.com/docs/core/runtime/dex-format
https://source.android.com/docs/core/runtime/dalvik-bytecode
https://source.android.com/docs/core/runtime/instruction-formats
--]]
require 'java.ffi.jni'		-- get cdefs
local ffi = require 'ffi'
local class = require 'ext.class'
local assert = require 'ext.assert'
local table = require 'ext.table'
local string = require 'ext.string'
local sha2 = require 'sha2'
local struct = require 'struct'

local JavaASM = require 'java.asm'

local java_blob = require 'java.blob'
local ReadBlobLE = java_blob.ReadBlobLE
local WriteBlobLE = java_blob.WriteBlobLE

local java_util = require 'java.util'
local deepCopy = java_util.deepCopy
local splitMethodJNISig = java_util.splitMethodJNISig
local getJNISig = java_util.getJNISig
local sigStrToObj = java_util.sigStrToObj
local setFlagsToObj = java_util.setFlagsToObj
local getFlagsFromObj = java_util.getFlagsFromObj
local classAccessFlags = java_util.nestedClassAccessFlags	-- dalvik's class access flags matches up with .class's nested-class access flags
local fieldAccessFlags = java_util.fieldAccessFlags
local methodAccessFlags = java_util.methodAccessFlags
local toLSlashSepSemName = java_util.toLSlashSepSemName
local toDotSepName  = java_util.toDotSepName


local jlong = ffi.typeof'jlong'


-- https://en.wikipedia.org/wiki/Adler-32
local function adler32(data, len)
	data = ffi.cast('uint8_t*', data)
    local a = 1
	local b = 0
	local MOD_ADLER = 65521
    for index=0,len-1 do
        a = (a + data[index]) % MOD_ADLER
        b = (b + a) % MOD_ADLER
    end
    return ffi.cast('uint32_t', bit.bor(bit.lshift(b, 16), a))
end


-- mixup of formats of type names and object names ...
-- array sizes split and duplicated across several unrelated data structures when pointing to the same array ...
-- how come I get the feeling that whoever designed the .dex file format didn't have a clue what they were doing.

local header_item = struct{
	anonymous = true,
	tostringFields = true,
	fields = {
		{name='magic', type='uint8_t[4]'},
		{name='version', type='uint32_t'},
		{name='checksum', type='uint32_t'},
		{name='sha1sig', type='uint8_t[20]'},
		{name='fileSize', type='uint32_t'},
		{name='headerSize', type='uint32_t'},
		{name='endianTag', type='uint32_t'},
		{name='numLinks', type='uint32_t'},
		{name='linkOfs', type='uint32_t'},
		{name='mapOfs', type='uint32_t'},
		{name='numStrings', type='uint32_t'},
		{name='stringOfsOfs', type='uint32_t'},
		{name='numTypes', type='uint32_t'},
		{name='typeOfs', type='uint32_t'},
		{name='numProtos', type='uint32_t'},
		{name='protoOfs', type='uint32_t'},
		{name='numFields', type='uint32_t'},
		{name='fieldOfs', type='uint32_t'},
		{name='numMethods', type='uint32_t'},
		{name='methodOfs', type='uint32_t'},
		{name='numClasses', type='uint32_t'},
		{name='classOfs', type='uint32_t'},
		{name='dataSize', type='uint32_t'},
		{name='datasOfs', type='uint32_t'},
		-- then there's supposed to be containerSize and headerOffset, but neither are present in the dex file I'm getting from android...
	},
}
local header_item_ptr = ffi.typeof('$*', header_item)

local map_item = struct{
	anonymous = true,
	tostringFields = true,
	fields = {
		{name='typeIndex', type='uint16_t'},
		{name='unused', type='uint16_t'},
		{name='count', type='uint32_t'},
		{name='offset', type='uint32_t'},
	},
}
local map_item_ptr = ffi.typeof('$*', map_item)

local proto_id_item = struct{
	anonymous = true,
	tostringFields = true,
	fields = {
		{name='shortyIndex', type='uint32_t'},
		{name='returnTypeIndex', type='uint32_t'},
		{name='argTypeListOfs', type='uint32_t'},
	},
}
local proto_id_item_ptr = ffi.typeof('$*', proto_id_item)

local field_id_item = struct{
	anonymous = true,
	tostringFields = true,
	fields = {
		{name='classIndex', type='uint16_t'},	-- type index
		{name='sigIndex', type='uint16_t'},		-- type index
		{name='nameIndex', type='uint32_t'},	-- string index
	},
}
local field_id_item_ptr = ffi.typeof('$*', field_id_item)

local method_id_item = struct{
	anonymous = true,
	tostringFields = true,
	fields = {
		{name='classIndex', type='uint16_t'},	-- type index
		{name='sigIndex', type='uint16_t'},		-- proto index
		{name='nameIndex', type='uint32_t'},	-- string index
	},
}
local method_id_item_ptr = ffi.typeof('$*', method_id_item)

local class_def_item = struct{
	anonymous = true,
	tostringFields = true,
	fields = {
		{name='thisClassIndex', type='uint32_t'},	-- type
		{name='accessFlags', type='uint32_t'},
		{name='superClassIndex', type='uint32_t'},	-- type
		{name='interfacesOfs', type='uint32_t'},
		{name='sourceFileIndex', type='uint32_t'},	-- string
		{name='annotationsOfs', type='uint32_t'},
		{name='classDataOfs', type='uint32_t'},
		{name='staticValuesOfs', type='uint32_t'},
	},
}
local class_def_item_ptr = ffi.typeof('$*', class_def_item)

-- just the header of code_item until its first variable-length array
local code_item = struct{
	anonymous = true,
	tostringFields = true,
	fields = {
		{name='maxRegs', type='uint16_t'},
		{name='regsIn', type='uint16_t'},
		{name='regsOut', type='uint16_t'},
		{name='numTries', type='uint16_t'},
		{name='debugInfoOfs', type='uint32_t'},
		{name='instSize', type='uint32_t'},	-- times two, since its in uint16 blocks
	},
}

local try_item = struct{
	anonymous = true,
	tostringFields = true,
	fields = {
		{name='startAddr', type='uint32_t'},
		{name='instSize', type='uint16_t'},
		{name='handlerOfs', type='uint16_t'},
	},
}

-- assumes o is cdata with ctype a struct
-- runs :fielditer() on o, flips all endian-ness fields.
-- swaps in place, idcare
local tmp = ffi.new'uint8_t[8]'
local function flipEndianStruct(o)
	for name, ctype, field in header:fielditer() do
		assert.type(ctype, 'string')  -- or use typeofs
		if ctype == 'int16_t'
		or ctype == 'uint16_t'
		or ctype == 'int32_t'
		or ctype == 'uint32_t'
		or ctype == 'int64_t'
		or ctype == 'uint64_t'
		then
			local ptr = ffi.cast('uint8_t*', o) + ffi.offsetof(o, name)
			local n = ffi.sizeof(ctype)
			for i=0,n-1 do
				tmp[i] = ptr[n-1-i]
			end
			o[name] = ffi.cast(ffi.typeof('$*', ffi.typeof(ctype)), tmp)[0]
		end
	end
end


local NO_INDEX = 0xffffffff

local mapListTypes = table{
	[0] = 'header_item',
	[1] = 'string_id_item',
	[2] = 'type_id_item',
	[3] = 'proto_id_item',
	[4] = 'field_id_item',
	[5] = 'method_id_item',
	[6] = 'class_def_item',
	[7] = 'call_site_id_item',
	[8] = 'method_handle_item',
	[0x1000] = 'map_list',
	[0x1001] = 'type_list',
	[0x1002] = 'annotation_set_ref_list',
	[0x1003] = 'annotation_set_item',
	[0x2000] = 'class_data_item',
	[0x2001] = 'code_item',
	[0x2002] = 'string_data_item',
	[0x2003] = 'debug_info_item',
	[0x2004] = 'annotation_item',
	[0x2005] = 'encoded_array_item',
	[0x2006] = 'annotations_directory_item',
	[0xF000] = 'hiddenapi_class_data_item',
}
local mapListTypeForName = mapListTypes:map(function(v,k)
	return k,v
end):setmetatable(nil)

local function instPushString(inst, stringIndex, asm)
	local str = asm.strings[1+stringIndex]
	if not str then
		inst:insert('!!! OOB string '..stringIndex)
	else
		inst:insert(str)
	end
end
local function instReadString(inst, index, asm)
	return (asm.findString(inst[index]))
end

local function instPushType(inst, typeIndex, asm)
	local typestr = asm.types[1+typeIndex]
	if not typestr then
		inst:insert('!!! OOB type '..typeIndex)
	else
		inst:insert(
			typestr -- toDotSepName(typestr)
		)
	end
end
local function instReadType(inst, index, asm)
	return (asm.findType(
		-- how about prims?  are they jni-signature style?
		inst[index]	-- toLSlashSepName(inst[index])
	))
end

local function instPushProto(inst, protoIndex, asm)
	local proto = asm.protos[1+protoIndex]
	if not proto then
		inst:insert('!!! OOB proto '..protoIndex)
	else
		inst:insert(proto)
	end
end
local function instReadProto(inst, index, asm)
	return (asm.findProto(inst[index]))
end

local function instPushField(inst, fieldIndex, asm)
	local field = asm.fields[1+fieldIndex]
	if not field then
		inst:insert('!!! OOB field '..fieldIndex)
	else
		inst:insert(field.class) --toDotSepName(field.class))
		inst:insert(field.name)
		inst:insert(field.sig)
	end
end
local function instReadField(inst, index, asm)
	return (asm.findField(
		toLSlashSepSemName(inst[index]),	-- class
		inst[index+1],					-- name
		inst[index+2]					-- sig
	))
end

local function instPushMethod(inst, methodIndex, asm)
	local method = asm.methods[1+methodIndex]
	if not method then
		inst:insert('!!! OOB method '..methodIndex)
	else
		inst:insert(method.class) --toDotSepName(method.class))
		inst:insert(method.name)
		inst:insert(method.sig)
	end
end
local function instReadMethod(inst, index, asm)
	if not inst[index]
	or not inst[index+1]
	or not inst[index+2]
	then
		error("instruction needs args "..index..'-'..(index+2)..': '..require'ext.tolua'(inst))
	end
	return (asm.findMethod(
		toLSlashSepSemName(inst[index]),	-- class
		inst[index+1],					-- name
		inst[index+2]					-- sig
	))
end


-- TODO even bother with this, why not just read/write numbers?
local function readreg(s)
	return (assert(tonumber(s:match'^v(.*)$', 16)))
end
local function readregopt(s, default)
	return s and (assert(tonumber(s:match'^v(.*)$', 16))) or default or 0
end


-- TODO TODO TODO
-- in .class jasmin asm, locals are still just numbers unless you use ".var" (which I do not yet support)
-- should I convert that to some sort of default 'v'-prefix like dalvik registers?
-- or should I give up on the 'v' prefix of dalvik and just use numbers here as well?
local function regname(index)
	assert.le(0, index)
	if index < 16 then return 'v'..bit.tohex(index, 1) end
	if index < 256 then return 'v'..bit.tohex(index, 2) end
	if index < 4096 then return 'v'..bit.tohex(index, 3) end
	if index < 65536 then return 'v'..bit.tohex(index, 4) end
	error("got an out of bound register: "..index)
end

local function tonibble(x)
	return bit.band(0xf, x),
		bit.band(0xf, bit.rshift(x, 4)),
		bit.band(0xf, bit.rshift(x, 8)),
		bit.band(0xf, bit.rshift(x, 12))
end

local function fromnibble(a,b,c,d)
	return bit.bor(
		bit.band(0xf, a),
		bit.lshift(bit.band(0xf, b or 0), 4),
		bit.lshift(bit.band(0xf, c or 0), 8),
		bit.lshift(bit.band(0xf, d or 0), 12)
	)
end

-- sign-extended to 32 bits...
local function signed4to32(x)
	if 0 ~= bit.band(8, x) then
		x = bit.bor(0xFFFFFFF0, x)
	end
	return x
end
local function signed8to32(x)
	if 0 ~= bit.band(0x80, x) then
		x = bit.bor(0xFFFFFF00, x)
	end
	return x
end


local Instr = class()
Instr.insert = table.insert
Instr.append = table.append
function Instr:traverse(visit) end	-- accumulate any unique constants, ... before we have to sort them ... and then re-visit them all again to get their correct indexes ... smh
function Instr:regsOut() return 0 end

-- 00|op
local Instr10x = Instr:subclass()
function Instr10x:read(hi, blob, asm)
	self:insert(hi)				-- throws away hi
end
function Instr10x:write(blob, asm)
	blob:writeu1(self[2] or 0)
end
function Instr10x:maxRegs() return 0 end

local Instr12x = Instr:subclass()
function Instr12x:read(hi, blob, asm)
	local A, B = tonibble(hi)
	self:insert(regname(A))
	self:insert(regname(B))
end
function Instr12x:write(blob, asm)
	blob:writeu1(fromnibble(
		readreg(self[2]),
		readreg(self[3])
	))
end

local Instr12x_1_1 = Instr12x:subclass()
function Instr12x_1_1:maxRegs()
	return math.max(readreg(self[2]), readreg(self[3])) + 1
end

local Instr12x_1_2 = Instr12x:subclass()
function Instr12x_1_2:maxRegs()
	return math.max(readreg(self[2]) + 1, readreg(self[3]) + 2)
end

local Instr12x_2_1 = Instr12x:subclass()
function Instr12x_2_1:maxRegs()
	return math.max(readreg(self[2]) + 2, readreg(self[3]) + 1)
end

local Instr12x_2_2 = Instr12x:subclass()
function Instr12x_2_2:maxRegs()
	return math.max(readreg(self[2]), readreg(self[3])) + 2
end

local Instr11n = Instr:subclass()
function Instr11n:read(hi, blob, asm)
	local A, B = tonibble(hi)
	B = signed4to32(B)
	self:insert(regname(A))
	self:insert(B)
end
function Instr11n:write(blob, asm)
	blob:writeu1(fromnibble(
		readreg(self[2]),
		self[3]
	))
end
function Instr11n:maxRegs()
	return readreg(self[2]) + 1
end

local Instr11x = Instr:subclass()
function Instr11x:read(hi, blob, asm)
	self:insert(regname(hi))
end
function Instr11x:write(blob, asm)
	blob:writeu1(readreg(self[2]))
end

local Instr11x_1 = Instr11x:subclass()
function Instr11x_1:maxRegs()
	return readreg(self[2]) + 1
end

local Instr11x_2 = Instr11x:subclass()
function Instr11x_2:maxRegs()
	return readreg(self[2]) + 2
end

local Instr10t = Instr:subclass()
function Instr10t:read(hi, blob, asm)
	self:insert(signed8to32(hi))					-- signed 8 bit branch offset
end
function Instr10t:write(blob, asm)
	blob:writes1(self[2])
end
function Instr10t:maxRegs() return 0 end

local Instr20t = Instr:subclass()
function Instr20t:read(hi, blob, asm)
	self:insert(blob:reads2())		-- signed
	self:insert(hi)					-- throws away hi
end
function Instr20t:write(blob, asm)
	blob:writeu1(self[3] or 0)	-- out of order, throw-away is last
	blob:writes2(self[2])
end
function Instr20t:maxRegs() return 0 end

local Instr22x = Instr:subclass()
function Instr22x:read(hi, blob, asm)
	self:insert(regname(hi))
	self:insert(regname(blob:readu2()))
end
function Instr22x:write(blob, asm)
	blob:writeu1(readreg(self[2]))
	blob:writeu2(readreg(self[3]))
end

local Instr22x_1 = Instr22x:subclass()
function Instr22x_1:maxRegs()
	return math.max(readreg(self[2]), readreg(self[3])) + 1
end

local Instr22x_2 = Instr22x:subclass()
function Instr22x_2:maxRegs()
	return math.max(readreg(self[2]), readreg(self[3])) + 2
end

local Instr21t = Instr:subclass()
function Instr21t:read(hi, blob, asm)
	self:insert(regname(hi))
	self:insert(blob:reads2())
end
function Instr21t:write(blob, asm)
	blob:writeu1(readreg(self[2]))
	blob:writes2(self[3])
end
function Instr21t:maxRegs()
	return readreg(self[2]) + 1
end

local Instr21s = Instr:subclass()
function Instr21s:read(hi, blob, asm)
	self:insert(regname(hi))
	self:insert(blob:readu2())	-- signed
end
function Instr21s:write(blob, asm)
	blob:writeu1(readreg(self[2]))
	blob:writeu2(self[3])
end

local Instr21s_1 = Instr21s:subclass()
function Instr21s_1:maxRegs()
	return readreg(self[2]) + 1
end

local Instr21s_2 = Instr21s:subclass()
function Instr21s_2:maxRegs()
	return readreg(self[2]) + 2
end

local Instr21h = Instr:subclass()
function Instr21h:read(hi, blob, asm)
	self:insert(regname(hi))
	self:insert(blob:readu2())
end
function Instr21h:write(blob, asm)
	blob:writeu1(readreg(self[2]))
	blob:writeu2(self[3])
end

local Instr21h_1 = Instr21h:subclass()
function Instr21h_1:maxRegs()
	return readreg(self[2]) + 1
end

local Instr21h_2 = Instr21h:subclass()
function Instr21h_2:maxRegs()
	return readreg(self[2]) + 2
end

local Instr21c_string = Instr:subclass()
function Instr21c_string:read(hi, blob, asm)
	self:insert(regname(hi))
	instPushString(self, blob:readu2(), asm)
end
function Instr21c_string:write(blob, asm)
	blob:writeu1(readreg(self[2]))
	blob:writeu2(instReadString(self, 3, asm))
end
function Instr21c_string:maxRegs()
	return readreg(self[2]) + 1
end
function Instr21c_string:traverse(visit)
	visit:string(self[3])
end

local Instr21c_type = Instr:subclass()
function Instr21c_type:read(hi, blob, asm)
	self:insert(regname(hi))
	instPushType(self, blob:readu2(), asm)
end
function Instr21c_type:write(blob, asm)
	blob:writeu1(readreg(self[2]))
	blob:writeu2(instReadType(self, 3, asm))
end
function Instr21c_type:maxRegs()
	return readreg(self[2]) + 1
end
function Instr21c_type:traverse(visit)
	visit:type(self[3])
end

local Instr21c_field = Instr:subclass()
function Instr21c_field:read(hi, blob, asm)
	self:insert(regname(hi))
	instPushField(self, blob:readu2(), asm)
end
function Instr21c_field:write(blob, asm)
	blob:writeu1(readreg(self[2]))
	blob:writeu2(instReadField(self, 3, asm))
end
function Instr21c_field:traverse(visit)
	visit:field(self[3], self[4], self[5])
end

local Instr21c_field_1 = Instr21c_field:subclass()
function Instr21c_field_1:maxRegs()
	return readreg(self[2]) + 1
end

local Instr21c_field_2 = Instr21c_field:subclass()
function Instr21c_field_2:maxRegs()
	return readreg(self[2]) + 2
end

-- instance-of A=dest reg, B=ref reg, C=type
-- new-array A=dest reg, B=size reg, C=type
local Instr22c_type = Instr:subclass()
function Instr22c_type:read(hi, blob, asm)
	local A, B = tonibble(hi)
	self:insert(regname(A))
	self:insert(regname(B))
	instPushType(self, blob:readu2(), asm)
end
function Instr22c_type:write(blob, asm)
	blob:writeu1(fromnibble(
		readreg(self[2]),
		readreg(self[3])
	))
	blob:writeu2(instReadType(self, 4, asm))
end
function Instr22c_type:maxRegs()
	return math.max(readreg(self[2]), readreg(self[3])) + 1
end
function Instr22c_type:traverse(visit)
	visit:type(self[4])
end

local Instr22c_field = Instr:subclass()
function Instr22c_field:read(hi, blob, asm)
	self:insert(regname(bit.band(hi, 0xf)))
	self:insert(regname(bit.band(bit.rshift(hi, 4), 0xf)))
	instPushField(self, blob:readu2(), asm)
end
function Instr22c_field:write(blob, asm)
	blob:writeu1(bit.bor(
		bit.band(0xf, readreg(self[2])),
		bit.lshift(bit.band(0xf, readreg(self[3])), 4)
	))
	blob:writeu2(instReadField(self, 4, asm))
end
function Instr22c_field:traverse(visit)
	visit:field(self[4], self[5], self[6])
end

local Instr22c_field_1 = Instr22c_field:subclass()
function Instr22c_field_1:maxRegs()
	return math.max(readreg(self[2]), readreg(self[3])) + 1
end

local Instr22c_field_2 = Instr22c_field:subclass()
function Instr22c_field_2:maxRegs()
	return math.max(readreg(self[2]) + 2, readreg(self[3]) + 1)
end

local Instr23x = Instr:subclass()
function Instr23x:read(hi, blob, asm)
	self:insert(regname(hi))
	self:insert(regname(blob:readu1()))	-- I'm sure I'm doign this wrong but it says vAA vBB vCC and that A is 8 bits and that the whole instruction reads 2 words, so *shrug* no sign of bitness of B or C
	self:insert(regname(blob:readu1()))
end
function Instr23x:write(blob, asm)
	blob:writeu1(readreg(self[2]))
	blob:writeu1(readreg(self[3]))
	blob:writeu1(readreg(self[4]))
end

-- 23x but for ...
-- cmp set int A for comparing int/float B and C
-- or array set int/float A for obj B and index C
-- or arith A = B op C for int/float
local Instr23x_1_1_1 = Instr23x:subclass()
function Instr23x_1_1_1:maxRegs()
	return math.max(
		readreg(self[2]),
		readreg(self[3]),
		readreg(self[4])
	) + 1
end

-- 23x but set int A for comparing long/double B and C, so its 2 reg size
local Instr23x_1_2_2 = Instr23x:subclass()
function Instr23x_1_2_2:maxRegs()
	return math.max(
		readreg(self[2]) + 1,
		readreg(self[3]) + 2,
		readreg(self[4]) + 2
	)
end

-- 23x but array setting A = long/double for array object B and index C
local Instr23x_2_1_1 = Instr23x:subclass()
function Instr23x_2_1_1:maxRegs()
	return math.max(
		readreg(self[2]) + 2,
		readreg(self[3]) + 1,
		readreg(self[4]) + 1
	)
end

local Instr23x_2_2_2 = Instr23x:subclass()
function Instr23x_2_2_2:maxRegs()
	return math.max(
		readreg(self[2]),
		readreg(self[3]),
		readreg(self[4])
	) + 2
end

local Instr22t = Instr:subclass()
function Instr22t:read(hi, blob, asm)
	self:insert(regname(bit.band(hi, 0xf)))
	self:insert(regname(bit.band(bit.rshift(hi, 4), 0xf)))
	self:insert(blob:reads2())
end
function Instr22t:write(blob, asm)
	blob:writeu1(bit.bor(
		bit.band(0xf, readreg(self[2])),
		bit.lshift(bit.band(0xf, readreg(self[3])), 4)
	))
	blob:writes2(self[4])
end
function Instr22t:maxRegs()
	return math.max(readreg(self[2]), readreg(self[3])) + 1
end

local Instr22s = Instr:subclass()
function Instr22s:read(hi, blob, asm)
	self:insert(regname(bit.band(hi, 0xf)))
	self:insert(regname(bit.band(bit.rshift(hi, 4), 0xf)))
	self:insert(blob:reads2())
end
function Instr22s:write(blob, asm)
	blob:writeu1(bit.bor(
		bit.band(0xf, readreg(self[2])),
		bit.lshift(bit.band(0xf, readreg(self[3])), 4)
	))
	blob:writes2(self[4])
end
function Instr22s:maxRegs()
	return math.max(readreg(self[2]), readreg(self[3])) + 1
end

local Instr22b = Instr:subclass()
function Instr22b:read(hi, blob, asm)
	self:insert(regname(bit.band(hi, 0xf)))
	self:insert(regname(bit.band(bit.rshift(hi, 4), 0xf)))
	self:insert(blob:reads2())	-- A is bits, B is 8 bits, C is 8 bits ... so C hi is unused? ... or C lo?
end
function Instr22b:write(blob, asm)
	blob:writeu1(bit.bor(
		bit.band(0xf, readreg(self[2])),
		bit.lshift(bit.band(0xf, readreg(self[3])), 4)
	))
	blob:writes2(self[4])
end
function Instr22b:maxRegs()
	return math.max(readreg(self[2]), readreg(self[3])) + 1
end

local Instr21c_method = Instr:subclass()
function Instr21c_method:read(hi, blob, asm)
	self:insert(regname(hi))
	instPushMethod(self, blob:readu2(), asm)
end
function Instr21c_method:write(blob, asm)
	blob:writeu1(readreg(self[2]))
	blob:writeu2(instReadMethod(self, 3, asm))
end
function Instr21c_method:maxRegs()
	return readreg(self[2]) + 1
end
function Instr21c_method:traverse(visit)
	visit:method(self[3], self[4], self[5])
end

local Instr21c_proto = Instr:subclass()
function Instr21c_proto:read(hi, blob, asm)
	self:insert(regname(hi))
	instPushProto(blob:readu2())
end
function Instr21c_proto:write(blob, asm)
	blob:writeu1(readreg(self[2]))
	blob:writeu2(instReadProto(self, 3, asm))
end
function Instr21c_proto:maxRegs()
	return readreg(self[2]) + 1
end
function Instr21c_proto:traverse(visit)
	visit:proto(self[3])
end

local Instr32x = Instr:subclass()
function Instr32x:read(hi, blob, asm)
	self:insert(regname(blob:readu2()))
	self:insert(regname(blob:readu2()))
	self:insert(hi)	-- NOTICE throws away hi
end
function Instr32x:write(blob, asm)
	blob:writeu1(self[4] or 0)
	blob:writeu2(readreg(self[2]))
	blob:writeu2(readreg(self[3]))
end

local Instr32x_1 = Instr32x:subclass()
function Instr32x_1:maxRegs()
	return math.max(readreg(self[2]), readreg(self[3])) + 1
end

local Instr32x_2 = Instr32x:subclass()
function Instr32x_2:maxRegs()
	return math.max(readreg(self[2]), readreg(self[3])) + 2
end

local Instr31i = Instr:subclass()
function Instr31i:read(hi, blob, asm)
	self:insert(regname(hi))
	self:insert(blob:reads4())	-- will this be 4-byte aligned?
end
function Instr31i:write(blob, asm)
	blob:writeu1(readreg(self[2]))
	blob:writes4(self[3])
end

local Instr31i_1 = Instr31i:subclass()
function Instr31i_1:maxRegs()
	return readreg(self[2]) + 1
end

local Instr31i_2 = Instr31i:subclass()
function Instr31i_2:maxRegs()
	return readreg(self[2]) + 2
end

local Instr31c_string = Instr:subclass()
function Instr31c_string:read(hi, blob, asm)
	self:insert(regname(hi))
	instPushString(self, blob:readu4(), asm)
end
function Instr31c_string:write(blob, asm)
	blob:writeu1(readreg(self[2]))
	blob:writeu4(instReadString(self, 3, asm))
end
function Instr31c_string:maxRegs()
	return readreg(self[2]) + 1
end
function Instr31c_string:traverse(visit)
	visit:string(self[3])
end

local Instr35c_type = Instr:subclass()
function Instr35c_type:read(hi, blob, asm)
	local G, A = tonibble(hi)
	if A < 1 or A > 5 then
		error(self[1].." expected 1-5 args, found "..A)
	end

	local typeIndex = blob:readu2()	-- B = type => self[2]
	instPushType(self, typeIndex, asm)

	-- will the 3rd byte be read if there is only 1 A?
	-- C..G are 4 bits each, so 20 bits total, so one of them is top nibble of 'hi' and the rest are another uint16 ...
	local x = blob:readu2()
	local C,D,E,F = tonibble(x)

	local regs = table{
		regname(C),
		regname(D),
		regname(E),
		regname(F),
		regname(G),
	}
	self:append(regs:sub(1, A))
end
function Instr35c_type:write(blob, asm)
	local A = #self - 2
	if A < 1 or A > 5 then
		error(self[1].." expected 1-5 args, found "..A)
	end
	local C = readregopt(self[3])
	local D = readregopt(self[4])
	local E = readregopt(self[5])
	local F = readregopt(self[6])
	local G = readregopt(self[7])

	blob:writeu1(fromnibble(G, A))
	blob:writeu2(instReadType(self, 2, asm))
	blob:writeu2(fromnibble(C, D, E, F))
end
function Instr35c_type:maxRegs()
	return math.max(
		readregopt(self[3], -1),
		readregopt(self[4], -1),
		readregopt(self[5], -1),
		readregopt(self[6], -1),
		readregopt(self[7], -1)
	) + 1
end
function Instr35c_type:traverse(visit)
	visit:type(self[2])
end

local Instr35c_method = Instr:subclass()
function Instr35c_method:read(hi, blob, asm)
	local G, A = tonibble(hi)
	if A < 0 or A > 5 then
		error(self[1].." expected 0-5 args, found "..A)
	end

	local methodIndex = blob:readu2()	-- B = method => self 2..4
	instPushMethod(self, methodIndex, asm)

	-- C..G are 4 bits each, so 20 bits total, so one of them is top nibble of 'hi' and the rest are another uint16 ...
	local x = blob:readu2()
	local C,D,E,F = tonibble(x)
	local regs = table{
		regname(C),
		regname(D),
		regname(E),
		regname(F),
		regname(G),
	}
	self:append(regs:sub(1, A))
end
function Instr35c_method:write(blob, asm)
	local A = #self - 4
	if A < 0 or A > 5 then
		error(self[1].." expected 0-5 args, found "..A)
	end
	local C = readregopt(self[5])
	local D = readregopt(self[6])
	local E = readregopt(self[7])
	local F = readregopt(self[8])
	local G = readregopt(self[9])

	blob:writeu1(fromnibble(G, A))
	blob:writeu2(instReadMethod(self, 2, asm))
	blob:writeu2(fromnibble(C, D, E, F))
end
function Instr35c_method:maxRegs()
	return math.max(
		readregopt(self[5], -1),
		readregopt(self[6], -1),
		readregopt(self[7], -1),
		readregopt(self[8], -1),
		readregopt(self[9], -1)
	) + 1
end
function Instr35c_method:regsOut()
	return #self - 4	-- 5 method args = 9 pieces to self
end
function Instr35c_method:traverse(visit)
	visit:method(self[2], self[3], self[4])
end

local Instr3rc_type = Instr:subclass()
function Instr3rc_type:read(hi, blob, asm)
	self:insert(hi)	-- A = array size and argument word count ... N = A + C - 1
	local typeIndex = blob:readu2()	-- B = type
	instPushType(self, typeIndex, asm)
	self:insert(regname(blob:readu2()))				-- C = first arg register
end
function Instr3rc_type:write(blob, asm)
	blob:writeu1(self[2])
	blob:writeu2(instReadType(self, 3, asm))
	blob:writeu2(readreg(self[4]))
end
function Instr3rc_type:maxRegs()
	return readreg(self[4]) + 1
end
function Instr3rc_type:traverse(visit)
	visit:type(self[3])
end

local Instr3rc_method = Instr:subclass()
function Instr3rc_method:read(hi, blob, asm)
	self:insert(regname(hi))	-- A = array size and argument word count ... N = A + C - 1
	local methodIndex = blob:readu2()	-- B = method
	instPushMethod(self, methodIndex, asm)
	self:insert(regname(blob:readu2()))				-- C = first arg register
end
function Instr3rc_method:write(blob, asm)
	blob:writeu1(readreg(self[2]))
	blob:writeu2(instReadMethod(self, 3, asm))
	blob:writeu2(readreg(self[6]))
end
function Instr3rc_method:maxRegs()
	return math.max(readreg(self[2]), readreg(self[6])) + 1
end
function Instr3rc_method:regsOut()
	return #self	-- TODO idk
end
function Instr3rc_method:traverse(visit)
	return visit:method(self[3], self[4], self[5])
end

local Instr31t = Instr:subclass()
function Instr31t:read(hi, blob, asm)
	self:insert(regname(hi))
	self:insert(blob:reads4())	-- signed branch offset to table data pseudo-instruction
end
function Instr31t:write(blob, asm)
	blob:writeu1(readreg(self[2]))
	blob:writes4(self[3])
end
function Instr31t:maxRegs()
	return readreg(self[2]) + 1
end

local Instr30t = Instr:subclass()
function Instr30t:read(hi, blob, asm)
	self:insert(blob:reads4())
	self:insert(hi)	-- NOTICE hi gets thrown away
end
function Instr30t:write(blob, asm)
	blob:writeu1(self[3] or 0)
	blob:writes4(self[2])
end
function Instr30t:maxRegs() return 0 end

local Instr35c_callsite = Instr:subclass()
function Instr35c_callsite:read(hi, blob, asm)
	-- TODO
	self:insert(hi)
	self:insert(blob:readu2())
	self:insert(blob:readu2())
end
function Instr35c_callsite:write(blob, asm)
	blob:writeu1(self[2])
	blob:writeu2(self[3])
	blob:writeu2(self[4])
end
function Instr35c_callsite:maxRegs() return 0 end	-- ???
function Instr35c_callsite:regsOut() return 0 end	-- ???

local Instr3rc_callsite = Instr:subclass()
function Instr3rc_callsite:read(hi, blob, asm)
	-- TODO
	self:insert(hi)
	self:insert(blob:readu2())
	self:insert(blob:readu2())
end
function Instr3rc_callsite:write(blob, asm)
	blob:writeu1(self[2])
	blob:writeu2(self[3])
	blob:writeu2(self[4])
end
function Instr3rc_callsite:maxRegs() return 0 end

local Instr45cc = Instr:subclass()
function Instr45cc:read(hi, blob, asm)
	local argc = bit.band(0xf, hi)
	if argc < 1 or argc > 5 then
		error(self[1].." expected 1-5 args, found "..argc)
	end

	local methodIndex = blob:readu2()	-- B = method (16 bits)
	instPushMethod(self, methodIndex, asm)

	-- D E F G are arg registers
	local x = blob:readu2()
	local regs = table{
		regname(bit.rshift(bit.band(0xf, hi), 4)),	-- C = receiver 4 bits
		regname(bit.band(x, 0xf)),
		regname(bit.band(bit.rshift(x, 4), 0xf)),
		regname(bit.band(bit.rshift(x, 8), 0xf)),
		regname(bit.band(bit.rshift(x, 12), 0xf)),
	}
	self:append(regs:sub(1, argc))

	local protoIndex = blob:readu2()	-- H = proto
	instPushProto(self, protoIndex, asm)
end
function Instr45cc:write(blob, asm)
	local argc = #self - 5
	if argc < 1 or argc > 5 then
		error(self[1].." expected 1-5 args, found "..argc)
	end

	blob:writeu1(bit.bor(
		argc,
		bit.lshift(bit.band(0xf, readregopt(self[5])), 4)
	))

	blob:writeu2(instReadMethod(self, 2, asm))

	blob:writeu2(bit.bor(
		bit.band(0xf, readregopt(self[6])),
		bit.lshift(bit.band(0xf, readregopt(self[7])), 4),
		bit.lshift(bit.band(0xf, readregopt(self[8])), 8),
		bit.lshift(bit.band(0xf, readregopt(self[9])), 12)
	))
	blob:writeu2(instReadProto(self, 11, asm))
end
function Instr45cc:maxRegs()
	return math.max(
		readregopt(self[5], -1),
		readregopt(self[6], -1),
		readregopt(self[7], -1),
		readregopt(self[8], -1),
		readregopt(self[9], -1)
	) + 1
end
function Instr45cc:regsOut()
	return #self - 4	-- idk really
end
function Instr45cc:traverse(visit)
	visit:method(self[2], self[3], self[4])
	visit:proto(self[11])
end

local Instr4rcc = Instr:subclass()
function Instr4rcc:read(hi, blob, asm)
	self:insert(hi)	-- arg word count 8 bits

	local methodIndex = blob:readu2()	-- B = method (16 bits)
	instPushMethod(self, methodIndex, asm)

	self:insert(regname(blob:readu2()))	-- C = receiver 16 bits

	local protoIndex = blob:readu2()	-- H = proto
	instPushProto(self, protoIndex, asm)
end
function Instr4rcc:write(blob, asm)
	blob:writeu1(bit.bor(
		bit.band(0xf, self[2]),
		bit.lshift(bit.band(0xf, readreg(self[6])), 4)
	))
	blob:writeu2(instReadMethod(self, 3, asm))
	blob:writeu2(readreg(self[7]))
	blob:writeu2(instReadProto(self, 8, asm))
end
function Instr4rcc:maxRegs()
	return readreg(self[6]) + 1
end
function Instr4rcc:traverse(visit)
	visit:method(self[3], self[4], self[5])
	visit:proto(self[8])
end

local Instr51l_long = Instr:subclass()
function Instr51l_long:read(hi, blob, asm)
	self:insert(regname(hi))
	self:insert(blob:read'jlong')
end
function Instr51l_long:write(blob, asm)
	blob:writeu1(readreg(self[2]))
	blob:write(jlong(self[3]))
end
function Instr51l_long:maxRegs()
	return readreg(self[2]) + 2	-- long/double takes 2 regs
end

local InstrClassesForOp = {
	[0x00] = Instr10x:subclass{name='nop'},									-- 00 10x	nop	 	Waste cycles.	Note: Data-bearing pseudo-instructions are tagged with this opcode, in which case the high-order byte of the opcode unit indicates the nature of the data. See "packed-switch-payload Format", "sparse-switch-payload Format", and "fill-array-data-payload Format" below.
	[0x01] = Instr12x_1_1:subclass{name='move'},							-- 01 12x	move vA, vB	A: destination register (4 bits) B: source register (4 bits)	Move the contents of one non-object register to another.
	[0x02] = Instr22x_1:subclass{name='move/from16'},						-- 02 22x	move/from16 vAA, vBBBB	A: destination register (8 bits) B: source register (16 bits)	Move the contents of one non-object register to another.
	[0x03] = Instr32x_1:subclass{name='move/16'},							-- 03 32x	move/16 vAAAA, vBBBB	A: destination register (16 bits) B: source register (16 bits)	Move the contents of one non-object register to another.
	[0x04] = Instr12x_2_2:subclass{name='move-wide'},						-- 04 12x	move-wide vA, vB	A: destination register pair (4 bits) B: source register pair (4 bits)	Move the contents of one register-pair to another. Note: It is legal to move from vN to either vN-1 or vN+1, so implementations must arrange for both halves of a register pair to be read before anything is written.
	[0x05] = Instr22x_2:subclass{name='move-wide/from16'},					-- 05 22x	move-wide/from16 vAA, vBBBB	A: destination register pair (8 bits) B: source register pair (16 bits)	Move the contents of one register-pair to another. Note: Implementation considerations are the same as move-wide, above.
	[0x06] = Instr32x_2:subclass{name='move-wide/16'},						-- 06 32x	move-wide/16 vAAAA, vBBBB	A: destination register pair (16 bits) B: source register pair (16 bits)	Move the contents of one register-pair to another. Note: Implementation considerations are the same as move-wide, above.
	[0x07] = Instr12x_1_1:subclass{name='move-object'},						-- 07 12x	move-object vA, vB	A: destination register (4 bits) B: source register (4 bits)	Move the contents of one object-bearing register to another.
	[0x08] = Instr22x_1:subclass{name='move-object/from16'},				-- 08 22x	move-object/from16 vAA, vBBBB	A: destination register (8 bits) B: source register (16 bits)	Move the contents of one object-bearing register to another.
	[0x09] = Instr32x_1:subclass{name='move-object/16'},					-- 09 32x	move-object/16 vAAAA, vBBBB	A: destination register (16 bits) B: source register (16 bits)	Move the contents of one object-bearing register to another.
	[0x0a] = Instr11x_1:subclass{name='move-result'},						-- 0a 11x	move-result vAA	A: destination register (8 bits)	Move the single-word non-object result of the most recent invoke-kind into the indicated register. This must be done as the instruction immediately after an invoke-kind whose (single-word, non-object) result is not to be ignored; anywhere else is invalid.
	[0x0b] = Instr11x_2:subclass{name='move-result-wide'},					-- 0b 11x	move-result-wide vAA	A: destination register pair (8 bits)	Move the double-word result of the most recent invoke-kind into the indicated register pair. This must be done as the instruction immediately after an invoke-kind whose (double-word) result is not to be ignored; anywhere else is invalid.
	[0x0c] = Instr11x_1:subclass{name='move-result-object'},				-- 0c 11x	move-result-object vAA	A: destination register (8 bits)	Move the object result of the most recent invoke-kind into the indicated register. This must be done as the instruction immediately after an invoke-kind or filled-new-array whose (object) result is not to be ignored; anywhere else is invalid.
	[0x0d] = Instr11x_1:subclass{name='move-exception'},					-- 0d 11x	move-exception vAA	A: destination register (8 bits)	Save a just-caught exception into the given register. This must be the first instruction of any exception handler whose caught exception is not to be ignored, and this instruction must only ever occur as the first instruction of an exception handler; anywhere else is invalid.
	[0x0e] = Instr10x:subclass{name='return-void'},							-- 0e 10x	return-void	 	Return from a void method.
	[0x0f] = Instr11x_1:subclass{name='return'},							-- 0f 11x	return vAA	A: return value register (8 bits)	Return from a single-width (32-bit) non-object value-returning method.
	[0x10] = Instr11x_2:subclass{name='return-wide'},						-- 10 11x	return-wide vAA	A: return value register-pair (8 bits)	Return from a double-width (64-bit) value-returning method.
	[0x11] = Instr11x_1:subclass{name='return-object'},						-- 11 11x	return-object vAA	A: return value register (8 bits)	Return from an object-returning method.
	[0x12] = Instr11n:subclass{name='const/4'},								-- 12 11n	const/4 vA, #+B	A: destination register (4 bits) B: signed int (4 bits)	Move the given literal value (sign-extended to 32 bits) into the specified register.
	[0x13] = Instr21s_1:subclass{name='const/16'},							-- 13 21s	const/16 vAA, #+BBBB	A: destination register (8 bits) B: signed int (16 bits)	Move the given literal value (sign-extended to 32 bits) into the specified register.
	[0x14] = Instr31i_1:subclass{name='const'},								-- 14 31i	const vAA, #+BBBBBBBB	A: destination register (8 bits) B: arbitrary 32-bit constant	Move the given literal value into the specified register.
	[0x15] = Instr21h_1:subclass{name='const/high16'},						-- 15 21h	const/high16 vAA, #+BBBB0000	A: destination register (8 bits) B: signed int (16 bits)	Move the given literal value (right-zero-extended to 32 bits) into the specified register.
	[0x16] = Instr21s_2:subclass{name='const-wide/16'},						-- 16 21s	const-wide/16 vAA, #+BBBB	A: destination register (8 bits) B: signed int (16 bits)	Move the given literal value (sign-extended to 64 bits) into the specified register-pair.
	[0x17] = Instr31i_2:subclass{name='const-wide/32'},						-- 17 31i	const-wide/32 vAA, #+BBBBBBBB	A: destination register (8 bits) B: signed int (32 bits)	Move the given literal value (sign-extended to 64 bits) into the specified register-pair.
	[0x18] = Instr51l_long:subclass{name='const-wide'},						-- 18 51l	const-wide vAA, #+BBBBBBBBBBBBBBBB	A: destination register (8 bits) B: arbitrary double-width (64-bit) constant	Move the given literal value into the specified register-pair.
	[0x19] = Instr21h_2:subclass{name='const-wide/high16'},					-- 19 21h	const-wide/high16 vAA, #+BBBB000000000000	A: destination register (8 bits) B: signed int (16 bits)	Move the given literal value (right-zero-extended to 64 bits) into the specified register-pair.
	[0x1a] = Instr21c_string:subclass{name='const-string'},					-- 1a 21c	const-string vAA, string@BBBB	A: destination register (8 bits) B: string index	Move a reference to the string specified by the given index into the specified register.
	[0x1b] = Instr31c_string:subclass{name='const-string/jumbo'},			-- 1b 31c	const-string/jumbo vAA, string@BBBBBBBB	A: destination register (8 bits) B: string index	Move a reference to the string specified by the given index into the specified register.
	[0x1c] = Instr21c_type:subclass{name='const-class'},					-- 1c 21c	const-class vAA, type@BBBB	A: destination register (8 bits) B: type index	Move a reference to the class specified by the given index into the specified register. In the case where the indicated type is primitive, this will store a reference to the primitive type's degenerate class.
	[0x1d] = Instr11x_1:subclass{name='monitor-enter'},						-- 1d 11x	monitor-enter vAA	A: reference-bearing register (8 bits)	Acquire the monitor for the indicated object.
	[0x1e] = Instr11x_1:subclass{name='monitor-exit'},						-- 1e 11x	monitor-exit vAA	A: reference-bearing register (8 bits)	Release the monitor for the indicated object. Note: If this instruction needs to throw an exception, it must do so as if the pc has already advanced past the instruction. It may be useful to think of this as the instruction successfully executing (in a sense), and the exception getting thrown after the instruction but before the next one gets a chance to run. This definition makes it possible for a method to use a monitor cleanup catch-all (e.g., finally) block as the monitor cleanup for that block itself, as a way to handle the arbitrary exceptions that might get thrown due to the historical implementation of Thread.stop(), while still managing to have proper monitor hygiene.
	[0x1f] = Instr21c_type:subclass{name='check-cast'},						-- 1f 21c	check-cast vAA, type@BBBB	A: reference-bearing register (8 bits) B: type index (16 bits)	Throw a ClassCastException if the reference in the given register cannot be cast to the indicated type. Note: Since A must always be a reference (and not a primitive value), this will necessarily fail at runtime (that is, it will throw an exception) if B refers to a primitive type.
	[0x20] = Instr22c_type:subclass{name='instance-of'},					-- 20 22c	instance-of vA, vB, type@CCCC	A: destination register (4 bits) B: reference-bearing register (4 bits) C: type index (16 bits)	Store in the given destination register 1 if the indicated reference is an instance of the given type, or 0 if not. Note: Since B must always be a reference (and not a primitive value), this will always result in 0 being stored if C refers to a primitive type.
	[0x21] = Instr12x_1_1:subclass{name='array-length'},					-- 21 12x	array-length vA, vB	A: destination register (4 bits) B: array reference-bearing register (4 bits)	Store in the given destination register the length of the indicated array, in entries
	[0x22] = Instr21c_type:subclass{name='new-instance'},					-- 22 21c	new-instance vAA, type@BBBB	A: destination register (8 bits) B: type index	Construct a new instance of the indicated type, storing a reference to it in the destination. The type must refer to a non-array class.
	[0x23] = Instr22c_type:subclass{name='new-array'},						-- 23 22c	new-array vA, vB, type@CCCC	A: destination register (4 bits) B: size register C: type index	Construct a new array of the indicated type and size. The type must be an array type.
	[0x24] = Instr35c_type:subclass{name='filled-new-array'},				-- 24 35c	filled-new-array {vC, vD, vE, vF, vG}, type@BBBB	A: array size and argument word count (4 bits) B: type index (16 bits) C..G: argument registers (4 bits each)	Construct an array of the given type and size, filling it with the supplied contents. The type must be an array type. The array's contents must be single-word (that is, no arrays of long or double, but reference types are acceptable). The constructed instance is stored as a "result" in the same way that the method invocation instructions store their results, so the constructed instance must be moved to a register with an immediately subsequent move-result-object instruction (if it is to be used).
	[0x25] = Instr3rc_type:subclass{name='filled-new-array/range'},			-- 25 3rc	filled-new-array/range {vCCCC .. vNNNN}, type@BBBB	A: array size and argument word count (8 bits) B: type index (16 bits) C: first argument register (16 bits) N = A + C - 1	Construct an array of the given type and size, filling it with the supplied contents. Clarifications and restrictions are the same as filled-new-array, described above.
	[0x26] = Instr31t:subclass{name='fill-array-data'},						-- 26 31t	fill-array-data vAA, +BBBBBBBB (with supplemental data as specified below in "fill-array-data-payload Format")	A: array reference (8 bits) B: signed "branch" offset to table data pseudo-instruction (32 bits)	Fill the given array with the indicated data. The reference must be to an array of primitives, and the data table must match it in type and must contain no more elements than will fit in the array. That is, the array may be larger than the table, and if so, only the initial elements of the array are set, leaving the remainder alone.
	[0x27] = Instr11x_1:subclass{name='throw'},								-- 27 11x	throw vAA	A: exception-bearing register (8 bits) Throw the indicated exception.
	[0x28] = Instr10t:subclass{name='goto'},								-- 28 10t	goto +AA	A: signed branch offset (8 bits)	Unconditionally jump to the indicated instruction. Note: The branch offset must not be 0. (A spin loop may be legally constructed either with goto/32 or by including a nop as a target before the branch.)
	[0x29] = Instr20t:subclass{name='goto/16'},								-- 29 20t	goto/16 +AAAA	A: signed branch offset (16 bits) Unconditionally jump to the indicated instruction. Note: The branch offset must not be 0. (A spin loop may be legally constructed either with goto/32 or by including a nop as a target before the branch.)
	[0x2a] = Instr30t:subclass{name='goto/32'},								-- 2a 30t	goto/32 +AAAAAAAA	A: signed branch offset (32 bits) Unconditionally jump to the indicated instruction.
	[0x2b] = Instr31t:subclass{name='packed-switch'},						-- 2b 31t	packed-switch vAA, +BBBBBBBB (with supplemental data as specified below in "packed-switch-payload Format")	A: register to test B: signed "branch" offset to table data pseudo-instruction (32 bits)	Jump to a new instruction based on the value in the given register, using a table of offsets corresponding to each value in a particular integral range, or fall through to the next instruction if there is no match.
	[0x2c] = Instr31t:subclass{name='sparse-switch'},						-- 2c 31t	sparse-switch vAA, +BBBBBBBB (with supplemental data as specified below in "sparse-switch-payload Format")	A: register to test B: signed "branch" offset to table data pseudo-instruction (32 bits)	Jump to a new instruction based on the value in the given register, using an ordered table of value-offset pairs, or fall through to the next instruction if there is no match.
	[0x2d] = Instr23x_1_1_1:subclass{name='cmpl-float'},					-- 2d 23x	cmpl-float vAA, vBB, vCC
	[0x2e] = Instr23x_1_1_1:subclass{name='cmpg-float'},					-- 2e 23x	cmpg-float vAA, vBB, vCC
	[0x2f] = Instr23x_1_2_2:subclass{name='cmpl-double'},					-- 2f 23x	cmpl-double vAA, vBB, vCC
	[0x30] = Instr23x_1_2_2:subclass{name='cmpg-double'},					-- 30 23x	cmpg-double vAA, vBB, vCC
	[0x31] = Instr23x_1_2_2:subclass{name='cmp-long'},						-- 31 23x	cmp-long vAA, vBB, vCC		A: destination register (8 bits) B: first source register or pair C: second source register or pair	Perform the indicated floating point or long comparison, setting a to 0 if b == c, 1 if b > c, or -1 if b < c. The "bias" listed for the floating point operations indicates how NaN comparisons are treated: "gt bias" instructions return 1 for NaN comparisons, and "lt bias" instructions return -1. For example, to check to see if floating point x < y it is advisable to use cmpg-float; a result of -1 indicates that the test was true, and the other values indicate it was false either due to a valid comparison or because one of the values was NaN.
	[0x32] = Instr22t:subclass{name='if-eq'},								-- 32 22t	if-eq vA, vB, +CCCC
	[0x33] = Instr22t:subclass{name='if-ne'},								-- 33 22t	if-ne vA, vB, +CCCC
	[0x34] = Instr22t:subclass{name='if-lt'},								-- 34 22t	if-lt vA, vB, +CCCC
	[0x35] = Instr22t:subclass{name='if-ge'},								-- 35 22t	if-ge vA, vB, +CCCC
	[0x36] = Instr22t:subclass{name='if-gt'},								-- 36 22t	if-gt vA, vB, +CCCC
	[0x37] = Instr22t:subclass{name='if-le'},								-- 37 22t	if-le vA, vB, +CCCC A: first register to test (4 bits) B: second register to test (4 bits) C: signed branch offset (16 bits)	Branch to the given destination if the given two registers' values compare as specified. Note: The branch offset must not be 0. (A spin loop may be legally constructed either by branching around a backward goto or by including a nop as a target before the branch.)
	[0x38] = Instr21t:subclass{name='if-eqz'},								-- 38 21t	if-eqz vAA, +BBBB
	[0x39] = Instr21t:subclass{name='if-nez'},								-- 39 21t	if-nez vAA, +BBBB
	[0x3a] = Instr21t:subclass{name='if-ltz'},								-- 3a 21t	if-ltz vAA, +BBBB
	[0x3b] = Instr21t:subclass{name='if-gez'},								-- 3b 21t	if-gez vAA, +BBBB
	[0x3c] = Instr21t:subclass{name='if-gtz'},								-- 3c 21t	if-gtz vAA, +BBBB
	[0x3d] = Instr21t:subclass{name='if-lez'},								-- 3d 21t	if-lez vAA, +BBBB A: register to test (8 bits) B: signed branch offset (16 bits)	Branch to the given destination if the given register's value compares with 0 as specified. Note: The branch offset must not be 0. (A spin loop may be legally constructed either by branching around a backward goto or by including a nop as a target before the branch.)
	[0x3e] = Instr10x:subclass{name='unused'},								-- 3e 10x	unused	 	unused
	[0x3f] = Instr10x:subclass{name='unused'},								-- 3f 10x	unused	 	unused
	[0x40] = Instr10x:subclass{name='unused'},								-- 40 10x	unused	 	unused
	[0x41] = Instr10x:subclass{name='unused'},								-- 41 10x	unused	 	unused
	[0x42] = Instr10x:subclass{name='unused'},								-- 42 10x	unused	 	unused
	[0x43] = Instr10x:subclass{name='unused'},								-- 43 10x	unused	 	unused
	[0x44] = Instr23x_1_1_1:subclass{name='aget'},							-- 44 23x	aget vAA, vBB, vCC
	[0x45] = Instr23x_2_1_1:subclass{name='aget-wide'},						-- 45 23x	aget-wide vAA, vBB, vCC
	[0x46] = Instr23x_1_1_1:subclass{name='aget-object'},					-- 46 23x	aget-object vAA, vBB, vCC
	[0x47] = Instr23x_1_1_1:subclass{name='aget-boolean'},					-- 47 23x	aget-boolean vAA, vBB, vCC
	[0x48] = Instr23x_1_1_1:subclass{name='aget-byte'},						-- 48 23x	aget-byte vAA, vBB, vCC
	[0x49] = Instr23x_1_1_1:subclass{name='aget-char'},						-- 49 23x	aget-char vAA, vBB, vCC
	[0x4a] = Instr23x_1_1_1:subclass{name='aget-short'},					-- 4a 23x	aget-short vAA, vBB, vCC
	[0x4b] = Instr23x_1_1_1:subclass{name='aput'},							-- 4b 23x	aput vAA, vBB, vCC
	[0x4c] = Instr23x_2_1_1:subclass{name='aput-wide'},						-- 4c 23x	aput-wide vAA, vBB, vCC
	[0x4d] = Instr23x_1_1_1:subclass{name='aput-object'},					-- 4d 23x	aput-object vAA, vBB, vCC
	[0x4e] = Instr23x_1_1_1:subclass{name='aput-boolean'},					-- 4e 23x	aput-boolean vAA, vBB, vCC
	[0x4f] = Instr23x_1_1_1:subclass{name='aput-byte'},						-- 4f 23x	aput-byte vAA, vBB, vCC
	[0x50] = Instr23x_1_1_1:subclass{name='aput-char'},						-- 50 23x	aput-char vAA, vBB, vCC
	[0x51] = Instr23x_1_1_1:subclass{name='aput-short'},					-- 51 23x	aput-short vAA, vBB, vCC	A: value register or pair; may be source or dest (8 bits) B: array register (8 bits) C: index register (8 bits)	Perform the identified array operation at the identified index of the given array, loading or storing into the value register.
	[0x52] = Instr22c_field_1:subclass{name='iget'},						-- 52 22c	iget vA, vB, field@CCCC
	[0x53] = Instr22c_field_2:subclass{name='iget-wide'},					-- 53 22c	iget-wide vA, vB, field@CCCC
	[0x54] = Instr22c_field_1:subclass{name='iget-object'},					-- 54 22c	iget-object vA, vB, field@CCCC
	[0x55] = Instr22c_field_1:subclass{name='iget-boolean'},				-- 55 22c	iget-boolean vA, vB, field@CCCC
	[0x56] = Instr22c_field_1:subclass{name='iget-byte'},					-- 56 22c	iget-byte vA, vB, field@CCCC
	[0x57] = Instr22c_field_1:subclass{name='iget-char'},					-- 57 22c	iget-char vA, vB, field@CCCC
	[0x58] = Instr22c_field_1:subclass{name='iget-short'},					-- 58 22c	iget-short vA, vB, field@CCCC
	[0x59] = Instr22c_field_1:subclass{name='iput'},						-- 59 22c	iput vA, vB, field@CCCC
	[0x5a] = Instr22c_field_2:subclass{name='iput-wide'},					-- 5a 22c	iput-wide vA, vB, field@CCCC
	[0x5b] = Instr22c_field_1:subclass{name='iput-object'},					-- 5b 22c	iput-object vA, vB, field@CCCC
	[0x5c] = Instr22c_field_1:subclass{name='iput-boolean'},				-- 5c 22c	iput-boolean vA, vB, field@CCCC
	[0x5d] = Instr22c_field_1:subclass{name='iput-byte'},					-- 5d 22c	iput-byte vA, vB, field@CCCC
	[0x5e] = Instr22c_field_1:subclass{name='iput-char'},					-- 5e 22c	iput-char vA, vB, field@CCCC
	[0x5f] = Instr22c_field_1:subclass{name='iput-short'},					-- 5f 22c	iput-short vA, vB, field@CCCC	A: value register or pair; may be source or dest (4 bits) B: object register (4 bits) C: instance field reference index (16 bits)	Perform the identified object instance field operation with the identified field, loading or storing into the value register. Note: These opcodes are reasonable candidates for static linking, altering the field argument to be a more direct offset.
	[0x60] = Instr21c_field_1:subclass{name='sget'},						-- 60 21c	sget vAA, field@BBBB
	[0x61] = Instr21c_field_2:subclass{name='sget-wide'},					-- 61 21c	sget-wide vAA, field@BBBB
	[0x62] = Instr21c_field_1:subclass{name='sget-object'},					-- 62 21c	sget-object vAA, field@BBBB
	[0x63] = Instr21c_field_1:subclass{name='sget-boolean'},				-- 63 21c	sget-boolean vAA, field@BBBB
	[0x64] = Instr21c_field_1:subclass{name='sget-byte'},					-- 64 21c	sget-byte vAA, field@BBBB
	[0x65] = Instr21c_field_1:subclass{name='sget-char'},					-- 65 21c	sget-char vAA, field@BBBB
	[0x66] = Instr21c_field_1:subclass{name='sget-short'},					-- 66 21c	sget-short vAA, field@BBBB
	[0x67] = Instr21c_field_1:subclass{name='sput'},						-- 67 21c	sput vAA, field@BBBB
	[0x68] = Instr21c_field_2:subclass{name='sput-wide'},					-- 68 21c	sput-wide vAA, field@BBBB
	[0x69] = Instr21c_field_1:subclass{name='sput-object'},					-- 69 21c	sput-object vAA, field@BBBB
	[0x6a] = Instr21c_field_1:subclass{name='sput-boolean'},				-- 6a 21c	sput-boolean vAA, field@BBBB
	[0x6b] = Instr21c_field_1:subclass{name='sput-byte'},					-- 6b 21c	sput-byte vAA, field@BBBB
	[0x6c] = Instr21c_field_1:subclass{name='sput-char'},					-- 6c 21c	sput-char vAA, field@BBBB
	[0x6d] = Instr21c_field_1:subclass{name='sput-short'},					-- 6d 21c	sput-short vAA, field@BBBB	A: value register or pair; may be source or dest (8 bits) B: static field reference index (16 bits)	Perform the identified object static field operation with the identified static field, loading or storing into the value register. Note: These opcodes are reasonable candidates for static linking, altering the field argument to be a more direct offset.
	[0x6e] = Instr35c_method:subclass{name='invoke-virtual'},				-- 6e 35c	invoke-virtual {vC, vD, vE, vF, vG}, meth@BBBB
	[0x6f] = Instr35c_method:subclass{name='invoke-super'},					-- 6f 35c	invoke-super {vC, vD, vE, vF, vG}, meth@BBBB
	[0x70] = Instr35c_method:subclass{name='invoke-direct'},				-- 70 35c	invoke-direct {vC, vD, vE, vF, vG}, meth@BBBB
	[0x71] = Instr35c_method:subclass{name='invoke-static'},				-- 71 35c	invoke-static {vC, vD, vE, vF, vG}, meth@BBBB
	[0x72] = Instr35c_method:subclass{name='invoke-interface'},				-- 72 35c	invoke-interface {vC, vD, vE, vF, vG}, meth@BBBB	A: argument word count (4 bits) B: method reference index (16 bits) C..G: argument registers (4 bits each)	Call the indicated method. The result (if any) may be stored with an appropriate move-result* variant as the immediately subsequent instruction. invoke-virtual is used to invoke a normal virtual method which is a method that isn't static, private or a constructor. When the method_id references a method of a non-interface class, invoke-super is used to invoke the closest superclass's virtual method (as opposed to the one with the same method_id in the calling class). The same method restrictions hold as for invoke-virtual. In Dex files version 037 or later, if the method_id refers to an interface method, invoke-super is used to invoke the most specific, non-overridden version of that method defined on that interface. The same method restrictions hold as for invoke-virtual. In Dex files prior to version 037, having an interface method_id is illegal and undefined. invoke-direct is used to invoke a non-static direct method (that is, an instance method that is by its nature non-overridable, namely either a private instance method or a constructor). invoke-static is used to invoke a static method (which is always considered a direct method). invoke-interface is used to invoke an interface method, that is, on an object whose concrete class isn't known, using a method_id that refers to an interface. Note: These opcodes are reasonable candidates for static linking, altering the method argument to be a more direct offset (or pair thereof).
	[0x73] = Instr10x:subclass{name='unused'},								-- 73 10x	unused		unused
	[0x74] = Instr3rc_method:subclass{name='invoke-virtual/range'},			-- 74 3rc	invoke-virtual/range {vCCCC .. vNNNN}, meth@BBBB
	[0x75] = Instr3rc_method:subclass{name='invoke-super/range'},			-- 75 3rc	invoke-super/range {vCCCC .. vNNNN}, meth@BBBB
	[0x76] = Instr3rc_method:subclass{name='invoke-direct/range'},			-- 76 3rc	invoke-direct/range {vCCCC .. vNNNN}, meth@BBBB
	[0x77] = Instr3rc_method:subclass{name='invoke-static/range'},			-- 77 3rc	invoke-static/range {vCCCC .. vNNNN}, meth@BBBB
	[0x78] = Instr3rc_method:subclass{name='invoke-interface/range'},		-- 78 3rc	invoke-interface/range {vCCCC .. vNNNN}, meth@BBBB	A: argument word count (8 bits) B: method reference index (16 bits) C: first argument register (16 bits) N = A + C - 1	Call the indicated method. See first invoke-kind description above for details, caveats, and suggestions.
	[0x79] = Instr10x:subclass{name='unused'},								-- 79 10x	unused		unused
	[0x7a] = Instr10x:subclass{name='unused'},								-- 7a 10x	unused		unused
	[0x7b] = Instr12x_1_1:subclass{name='neg-int'},							-- 7b 12x	neg-int vA, vB
	[0x7c] = Instr12x_1_1:subclass{name='not-int'},							-- 7c 12x	not-int vA, vB
	[0x7d] = Instr12x_2_2:subclass{name='neg-long'},						-- 7d 12x	neg-long vA, vB
	[0x7e] = Instr12x_2_2:subclass{name='not-long'},						-- 7e 12x	not-long vA, vB
	[0x7f] = Instr12x_1_1:subclass{name='neg-float'},						-- 7f 12x	neg-float vA, vB
	[0x80] = Instr12x_2_2:subclass{name='neg-double'},						-- 80 12x	neg-double vA, vB
	[0x81] = Instr12x_2_1:subclass{name='int-to-long'},						-- 81 12x	int-to-long vA, vB
	[0x82] = Instr12x_1_1:subclass{name='int-to-float'},					-- 82 12x	int-to-float vA, vB
	[0x83] = Instr12x_2_1:subclass{name='int-to-double'},					-- 83 12x	int-to-double vA, vB
	[0x84] = Instr12x_1_2:subclass{name='long-to-int'},						-- 84 12x	long-to-int vA, vB
	[0x85] = Instr12x_1_2:subclass{name='long-to-float'},					-- 85 12x	long-to-float vA, vB
	[0x86] = Instr12x_2_2:subclass{name='long-to-double'},					-- 86 12x	long-to-double vA, vB
	[0x87] = Instr12x_1_1:subclass{name='float-to-int'},					-- 87 12x	float-to-int vA, vB
	[0x88] = Instr12x_2_1:subclass{name='float-to-long'},					-- 88 12x	float-to-long vA, vB
	[0x89] = Instr12x_2_1:subclass{name='float-to-double'},					-- 89 12x	float-to-double vA, vB
	[0x8a] = Instr12x_1_2:subclass{name='double-to-int'},					-- 8a 12x	double-to-int vA, vB
	[0x8b] = Instr12x_2_2:subclass{name='double-to-long'},					-- 8b 12x	double-to-long vA, vB
	[0x8c] = Instr12x_1_2:subclass{name='double-to-float'},					-- 8c 12x	double-to-float vA, vB
	[0x8d] = Instr12x_1_1:subclass{name='int-to-byte'},						-- 8d 12x	int-to-byte vA, vB
	[0x8e] = Instr12x_1_1:subclass{name='int-to-char'},						-- 8e 12x	int-to-char vA, vB
	[0x8f] = Instr12x_1_1:subclass{name='int-to-short'},					-- 8f 12x	int-to-short vA, vB	A: destination register or pair (4 bits) B: source register or pair (4 bits)	Perform the identified unary operation on the source register, storing the result in the destination register.
	[0x90] = Instr23x_1_1_1:subclass{name='add-int'},						-- 90 23x	add-int vAA, vBB, vCC
	[0x91] = Instr23x_1_1_1:subclass{name='sub-int'},						-- 91 23x	sub-int vAA, vBB, vCC
	[0x92] = Instr23x_1_1_1:subclass{name='mul-int'},						-- 92 23x	mul-int vAA, vBB, vCC
	[0x93] = Instr23x_1_1_1:subclass{name='div-int'},						-- 93 23x	div-int vAA, vBB, vCC
	[0x94] = Instr23x_1_1_1:subclass{name='rem-int'},						-- 94 23x	rem-int vAA, vBB, vCC
	[0x95] = Instr23x_1_1_1:subclass{name='and-int'},						-- 95 23x	and-int vAA, vBB, vCC
	[0x96] = Instr23x_1_1_1:subclass{name='or-int'},						-- 96 23x	or-int vAA, vBB, vCC
	[0x97] = Instr23x_1_1_1:subclass{name='xor-int'},						-- 97 23x	xor-int vAA, vBB, vCC
	[0x98] = Instr23x_1_1_1:subclass{name='shl-int'},						-- 98 23x	shl-int vAA, vBB, vCC
	[0x99] = Instr23x_1_1_1:subclass{name='shr-int'},						-- 99 23x	shr-int vAA, vBB, vCC
	[0x9a] = Instr23x_1_1_1:subclass{name='ushr-int'},						-- 9a 23x	ushr-int vAA, vBB, vCC
	[0x9b] = Instr23x_2_2_2:subclass{name='add-long'},						-- 9b 23x	add-long vAA, vBB, vCC
	[0x9c] = Instr23x_2_2_2:subclass{name='sub-long'},						-- 9c 23x	sub-long vAA, vBB, vCC
	[0x9d] = Instr23x_2_2_2:subclass{name='mul-long'},						-- 9d 23x	mul-long vAA, vBB, vCC
	[0x9e] = Instr23x_2_2_2:subclass{name='div-long'},						-- 9e 23x	div-long vAA, vBB, vCC
	[0x9f] = Instr23x_2_2_2:subclass{name='rem-long'},						-- 9f 23x	rem-long vAA, vBB, vCC
	[0xa0] = Instr23x_2_2_2:subclass{name='and-long'},						-- a0 23x	and-long vAA, vBB, vCC
	[0xa1] = Instr23x_2_2_2:subclass{name='or-long'},						-- a1 23x	or-long vAA, vBB, vCC
	[0xa2] = Instr23x_2_2_2:subclass{name='xor-long'},						-- a2 23x	xor-long vAA, vBB, vCC
	[0xa3] = Instr23x_2_2_2:subclass{name='shl-long'},						-- a3 23x	shl-long vAA, vBB, vCC
	[0xa4] = Instr23x_2_2_2:subclass{name='shr-long'},						-- a4 23x	shr-long vAA, vBB, vCC
	[0xa5] = Instr23x_2_2_2:subclass{name='ushr-long'},						-- a5 23x	ushr-long vAA, vBB, vCC
	[0xa6] = Instr23x_1_1_1:subclass{name='add-float'},						-- a6 23x	add-float vAA, vBB, vCC
	[0xa7] = Instr23x_1_1_1:subclass{name='sub-float'},						-- a7 23x	sub-float vAA, vBB, vCC
	[0xa8] = Instr23x_1_1_1:subclass{name='mul-float'},						-- a8 23x	mul-float vAA, vBB, vCC
	[0xa9] = Instr23x_1_1_1:subclass{name='div-float'},						-- a9 23x	div-float vAA, vBB, vCC
	[0xaa] = Instr23x_1_1_1:subclass{name='rem-float'},						-- aa 23x	rem-float vAA, vBB, vCC
	[0xab] = Instr23x_2_2_2:subclass{name='add-double'},					-- ab 23x	add-double vAA, vBB, vCC
	[0xac] = Instr23x_2_2_2:subclass{name='sub-double'},					-- ac 23x	sub-double vAA, vBB, vCC
	[0xad] = Instr23x_2_2_2:subclass{name='mul-double'},					-- ad 23x	mul-double vAA, vBB, vCC
	[0xae] = Instr23x_2_2_2:subclass{name='div-double'},					-- ae 23x	div-double vAA, vBB, vCC
	[0xaf] = Instr23x_2_2_2:subclass{name='rem-double'},					-- af 23x	rem-double vAA, vBB, vCC	A: destination register or pair (8 bits) B: first source register or pair (8 bits) C: second source register or pair (8 bits)	Perform the identified binary operation on the two source registers, storing the result in the destination register. Note: Contrary to other -long mathematical operations (which take register pairs for both their first and their second source), shl-long, shr-long, and ushr-long take a register pair for their first source (the value to be shifted), but a single register for their second source (the shifting distance).
	[0xb0] = Instr12x_1_1:subclass{name='add-int/2addr'},					-- b0 12x	add-int/2addr vA, vB
	[0xb1] = Instr12x_1_1:subclass{name='sub-int/2addr'},					-- b1 12x	sub-int/2addr vA, vB
	[0xb2] = Instr12x_1_1:subclass{name='mul-int/2addr'},					-- b2 12x	mul-int/2addr vA, vB
	[0xb3] = Instr12x_1_1:subclass{name='div-int/2addr'},					-- b3 12x	div-int/2addr vA, vB
	[0xb4] = Instr12x_1_1:subclass{name='rem-int/2addr'},					-- b4 12x	rem-int/2addr vA, vB
	[0xb5] = Instr12x_1_1:subclass{name='and-int/2addr'},					-- b5 12x	and-int/2addr vA, vB
	[0xb6] = Instr12x_1_1:subclass{name='or-int/2addr'},					-- b6 12x	or-int/2addr vA, vB
	[0xb7] = Instr12x_1_1:subclass{name='xor-int/2addr'},					-- b7 12x	xor-int/2addr vA, vB
	[0xb8] = Instr12x_1_1:subclass{name='shl-int/2addr'},					-- b8 12x	shl-int/2addr vA, vB
	[0xb9] = Instr12x_1_1:subclass{name='shr-int/2addr'},					-- b9 12x	shr-int/2addr vA, vB
	[0xba] = Instr12x_1_1:subclass{name='ushr-int/2addr'},					-- ba 12x	ushr-int/2addr vA, vB
	[0xbb] = Instr12x_2_2:subclass{name='add-long/2addr'},					-- bb 12x	add-long/2addr vA, vB
	[0xbc] = Instr12x_2_2:subclass{name='sub-long/2addr'},					-- bc 12x	sub-long/2addr vA, vB
	[0xbd] = Instr12x_2_2:subclass{name='mul-long/2addr'},					-- bd 12x	mul-long/2addr vA, vB
	[0xbe] = Instr12x_2_2:subclass{name='div-long/2addr'},					-- be 12x	div-long/2addr vA, vB
	[0xbf] = Instr12x_2_2:subclass{name='rem-long/2addr'},					-- bf 12x	rem-long/2addr vA, vB
	[0xc0] = Instr12x_2_2:subclass{name='and-long/2addr'},					-- c0 12x	and-long/2addr vA, vB
	[0xc1] = Instr12x_2_2:subclass{name='or-long/2addr'},					-- c1 12x	or-long/2addr vA, vB
	[0xc2] = Instr12x_2_2:subclass{name='xor-long/2addr'},					-- c2 12x	xor-long/2addr vA, vB
	[0xc3] = Instr12x_2_2:subclass{name='shl-long/2addr'},					-- c3 12x	shl-long/2addr vA, vB
	[0xc4] = Instr12x_2_2:subclass{name='shr-long/2addr'},					-- c4 12x	shr-long/2addr vA, vB
	[0xc5] = Instr12x_2_2:subclass{name='ushr-long/2addr'},					-- c5 12x	ushr-long/2addr vA, vB
	[0xc6] = Instr12x_1_1:subclass{name='add-float/2addr'},					-- c6 12x	add-float/2addr vA, vB
	[0xc7] = Instr12x_1_1:subclass{name='sub-float/2addr'},					-- c7 12x	sub-float/2addr vA, vB
	[0xc8] = Instr12x_1_1:subclass{name='mul-float/2addr'},					-- c8 12x	mul-float/2addr vA, vB
	[0xc9] = Instr12x_1_1:subclass{name='div-float/2addr'},					-- c9 12x	div-float/2addr vA, vB
	[0xca] = Instr12x_1_1:subclass{name='rem-float/2addr'},					-- ca 12x	rem-float/2addr vA, vB
	[0xcb] = Instr12x_2_2:subclass{name='add-double/2addr'},				-- cb 12x	add-double/2addr vA, vB
	[0xcc] = Instr12x_2_2:subclass{name='sub-double/2addr'},				-- cc 12x	sub-double/2addr vA, vB
	[0xcd] = Instr12x_2_2:subclass{name='mul-double/2addr'},				-- cd 12x	mul-double/2addr vA, vB
	[0xce] = Instr12x_2_2:subclass{name='div-double/2addr'},				-- ce 12x	div-double/2addr vA, vB
	[0xcf] = Instr12x_2_2:subclass{name='rem-double/2addr'},				-- cf 12x	rem-double/2addr vA, vB	A: destination and first source register or pair (4 bits) B: second source register or pair (4 bits)	Perform the identified binary operation on the two source registers, storing the result in the first source register. Note: Contrary to other -long/2addr mathematical operations (which take register pairs for both their destination/first source and their second source), shl-long/2addr, shr-long/2addr, and ushr-long/2addr take a register pair for their destination/first source (the value to be shifted), but a single register for their second source (the shifting distance).
	[0xd0] = Instr22s:subclass{name='add-int/lit16'},						-- d0 22s	add-int/lit16 vA, vB, #+CCCC
	[0xd1] = Instr22s:subclass{name='rsub-int'},							-- d1 22s	rsub-int vA, vB, #+CCCC (reverse subtract)
	[0xd2] = Instr22s:subclass{name='mul-int/lit16'},						-- d2 22s	mul-int/lit16 vA, vB, #+CCCC
	[0xd3] = Instr22s:subclass{name='div-int/lit16'},						-- d3 22s	div-int/lit16 vA, vB, #+CCCC
	[0xd4] = Instr22s:subclass{name='rem-int/lit16'},						-- d4 22s	rem-int/lit16 vA, vB, #+CCCC
	[0xd5] = Instr22s:subclass{name='and-int/lit16'},						-- d5 22s	and-int/lit16 vA, vB, #+CCCC
	[0xd6] = Instr22s:subclass{name='or-int/lit16'},						-- d6 22s	or-int/lit16 vA, vB, #+CCCC
	[0xd7] = Instr22s:subclass{name='xor-int/lit16'},						-- d7 22s	xor-int/lit16 vA, vB, #+CCCC	A: destination register (4 bits) B: source register (4 bits) C: signed int constant (16 bits)	Perform the indicated binary op on the indicated register (first argument) and literal value (second argument), storing the result in the destination register. Note: rsub-int does not have a suffix since this version is the main opcode of its family. Also, see below for details on its semantics.
	[0xd8] = Instr22b:subclass{name='add-int/lit8'},						-- d8 22b	add-int/lit8 vAA, vBB, #+CC
	[0xd9] = Instr22b:subclass{name='rsub-int/lit8'},						-- d9 22b	rsub-int/lit8 vAA, vBB, #+CC
	[0xda] = Instr22b:subclass{name='mul-int/lit8'},						-- da 22b	mul-int/lit8 vAA, vBB, #+CC
	[0xdb] = Instr22b:subclass{name='div-int/lit8'},						-- db 22b	div-int/lit8 vAA, vBB, #+CC
	[0xdc] = Instr22b:subclass{name='rem-int/lit8'},						-- dc 22b	rem-int/lit8 vAA, vBB, #+CC
	[0xdd] = Instr22b:subclass{name='and-int/lit8'},						-- dd 22b	and-int/lit8 vAA, vBB, #+CC
	[0xde] = Instr22b:subclass{name='or-int/lit8'},							-- de 22b	or-int/lit8 vAA, vBB, #+CC
	[0xdf] = Instr22b:subclass{name='xor-int/lit8'},						-- df 22b	xor-int/lit8 vAA, vBB, #+CC
	[0xe0] = Instr22b:subclass{name='shl-int/lit8'},						-- e0 22b	shl-int/lit8 vAA, vBB, #+CC
	[0xe1] = Instr22b:subclass{name='shr-int/lit8'},						-- e1 22b	shr-int/lit8 vAA, vBB, #+CC
	[0xe2] = Instr22b:subclass{name='ushr-int/lit8'},						-- e2 22b	ushr-int/lit8 vAA, vBB, #+CC	A: destination register (8 bits) B: source register (8 bits) C: signed int constant (8 bits)	Perform the indicated binary op on the indicated register (first argument) and literal value (second argument), storing the result in the destination register. Note: See below for details on the semantics of rsub-int.
	[0xe3] = Instr10x:subclass{name='unused'},								-- e3 10x	unused	 	unused
	[0xe4] = Instr10x:subclass{name='unused'},								-- e4 10x	unused	 	unused
	[0xe5] = Instr10x:subclass{name='unused'},								-- e5 10x	unused	 	unused
	[0xe6] = Instr10x:subclass{name='unused'},								-- e6 10x	unused	 	unused
	[0xe7] = Instr10x:subclass{name='unused'},								-- e7 10x	unused	 	unused
	[0xe8] = Instr10x:subclass{name='unused'},								-- e8 10x	unused	 	unused
	[0xe9] = Instr10x:subclass{name='unused'},								-- e9 10x	unused	 	unused
	[0xea] = Instr10x:subclass{name='unused'},								-- ea 10x	unused	 	unused
	[0xeb] = Instr10x:subclass{name='unused'},								-- eb 10x	unused	 	unused
	[0xec] = Instr10x:subclass{name='unused'},								-- ec 10x	unused	 	unused
	[0xed] = Instr10x:subclass{name='unused'},								-- ed 10x	unused	 	unused
	[0xee] = Instr10x:subclass{name='unused'},								-- ee 10x	unused	 	unused
	[0xef] = Instr10x:subclass{name='unused'},								-- ef 10x	unused	 	unused
	[0xf0] = Instr10x:subclass{name='unused'},								-- f0 10x	unused	 	unused
	[0xf1] = Instr10x:subclass{name='unused'},								-- f1 10x	unused	 	unused
	[0xf2] = Instr10x:subclass{name='unused'},								-- f2 10x	unused	 	unused
	[0xf3] = Instr10x:subclass{name='unused'},								-- f3 10x	unused	 	unused
	[0xf4] = Instr10x:subclass{name='unused'},								-- f4 10x	unused	 	unused
	[0xf5] = Instr10x:subclass{name='unused'},								-- f5 10x	unused	 	unused
	[0xf6] = Instr10x:subclass{name='unused'},								-- f6 10x	unused	 	unused
	[0xf7] = Instr10x:subclass{name='unused'},								-- f7 10x	unused	 	unused
	[0xf8] = Instr10x:subclass{name='unused'},								-- f8 10x	unused	 	unused
	[0xf9] = Instr10x:subclass{name='unused'},								-- f9 10x	unused	 	unused
	[0xfa] = Instr45cc:subclass{name='invoke-polymorphic'},					-- fa 45cc	invoke-polymorphic {vC, vD, vE, vF, vG}, meth@BBBB, proto@HHHH	A: argument word count (4 bits) B: method reference index (16 bits) C: receiver (4 bits) D..G: argument registers (4 bits each) H: prototype reference index (16 bits)	Invoke the indicated signature polymorphic method. The result (if any) may be stored with an appropriate move-result* variant as the immediately subsequent instruction. The method reference must be to a signature polymorphic method, such as java.lang.invoke.MethodHandle.invoke or java.lang.invoke.MethodHandle.invokeExact. The receiver must be an object supporting the signature polymorphic method being invoked. The prototype reference describes the argument types provided and the expected return type. The invoke-polymorphic bytecode may raise exceptions when it executes. The exceptions are described in the API documentation for the signature polymorphic method being invoked. Present in Dex files from version 038 onwards.
	[0xfb] = Instr4rcc:subclass{name='invoke-polymorphic/range'},			-- fb 4rcc	invoke-polymorphic/range {vCCCC .. vNNNN}, meth@BBBB, proto@HHHH	A: argument word count (8 bits) B: method reference index (16 bits) C: receiver (16 bits) H: prototype reference index (16 bits) N = A + C - 1	Invoke the indicated method handle. See the invoke-polymorphic description above for details. Present in Dex files from version 038 onwards.
	[0xfc] = Instr35c_callsite:subclass{name='invoke-custom'},				-- fc 35c	invoke-custom {vC, vD, vE, vF, vG}, call_site@BBBB	A: argument word count (4 bits) B: call site reference index (16 bits) C..G: argument registers (4 bits each)	Resolves and invokes the indicated call site. The result from the invocation (if any) may be stored with an appropriate move-result* variant as the immediately subsequent instruction. This instruction executes in two phases: call site resolution and call site invocation. Call site resolution checks whether the indicated call site has an associated java.lang.invoke.CallSite instance. If not, the bootstrap linker method for the indicated call site is invoked using arguments present in the DEX file (see call_site_item). The bootstrap linker method returns a java.lang.invoke.CallSite instance that will then be associated with the indicated call site if no association exists. Another thread may have already made the association first, and if so execution of the instruction continues with the first associated java.lang.invoke.CallSite instance. Call site invocation is made on the java.lang.invoke.MethodHandle target of the resolved java.lang.invoke.CallSite instance. The target is invoked as if executing invoke-polymorphic (described above) using the method handle and arguments to the invoke-custom instruction as the arguments to an exact method handle invocation. Exceptions raised by the bootstrap linker method are wrapped in a java.lang.BootstrapMethodError. A BootstrapMethodError is also raised if: the bootstrap linker method fails to return a java.lang.invoke.CallSite instance. the returned java.lang.invoke.CallSite has a null method handle target. the method handle target is not of the requested type. Present in Dex files from version 038 onwards.
	[0xfd] = Instr3rc_callsite:subclass{name='invoke-custom/range'},		-- fd 3rc	invoke-custom/range {vCCCC .. vNNNN}, call_site@BBBB	A: argument word count (8 bits) B: call site reference index (16 bits) C: first argument register (16-bits) N = A + C - 1	Resolve and invoke a call site. See the invoke-custom description above for details. Present in Dex files from version 038 onwards.
	[0xfe] = Instr21c_method:subclass{name='const-method-handle'},			-- fe 21c	const-method-handle vAA, method_handle@BBBB	A: destination register (8 bits) B: method handle index (16 bits)	Move a reference to the method handle specified by the given index into the specified register. Present in Dex files from version 039 onwards.
	[0xff] = Instr21c_proto:subclass{name='const-method-type'},				-- ff 21c	const-method-type vAA, proto@BBBB	A: destination register (8 bits) B: method prototype reference (16 bits)	Move a reference to the method prototype specified by the given index into the specified register. Present in Dex files from version 039 onwards.
}
local opForInstName = table.map(InstrClassesForOp, function(cl, op)
	return op, cl.name
end)

local JavaASMDex = JavaASM:subclass()
JavaASMDex.__name = 'JavaASMDex'

JavaASMDex.InstrClassesForOp =  InstrClassesForOp
JavaASMDex.opForInstName =  opForInstName

--[[
similar as JavaASMClass
key differences in ASMDex vs ASMClass:
- .dex files can have multiple classes, so
- - they will have a .class table holding the, thisClass, superClass, and class access flags
- - each method and field will have a .class reference
- internally .dex uses some weird convoluted arg type list and "shorty" (smh Google...) arg string that is a typical Java function jni arg signature string but with a) return type first, b) parenthesis removed, and c) all class names removed.
- .dex methods have "maxRegs", "regsIn", "regsOut" where .class methods have "maxLocals" and "maxStacks"
- the instruction sets are different
- optional attributes differ
--]]


-------------------------------- READING --------------------------------



function JavaASMDex:readData(data)
	local blob = ReadBlobLE(data)

	local header = blob:read(header_item)
	assert.eq(ffi.string(header.magic, 4), 'dex\n')
--DEBUG:print('version', bit.tohex(header.version, 8)))
--DEBUG:print('checksum = 0x'..bit.tohex(header.checksum, 8))
--DEBUG:print('sha1sig', string.hex(ffi.string(header.sha1sig, 20)))
--DEBUG:print('fileSize', header.fileSize)
--DEBUG:print('headerSize', header.headerSize)
--DEBUG:print('endianTag = 0x'..bit.tohex(header.endianTag, 8))
	local endianFlipped
	if header.endianTag == 0x78563412 then
io.stderr:write('endian flipped...\n')
		endianFlipped = true
error[[
TODO
I will want blob:read's on primitive integrals to flip endian,
but I won't want it to flip order when reading structs
(so that I can next call flipEndianStruct() to flip individual fields)
or
I could change all fields from prim to some kind of endian-ness wrapper that needs an extra read()/write() or something...
but that'd get ugly fast...
and
honesty structs are only useful in a few places
but are not useful with Uleb128's
]]
		-- ... then our endian-ness doesn't match our architecture so we have to flip all fields
		flipEndianStruct(header)
	end
	assert.eq(header.endianTag, 0x12345678, 'endian is a bad value')

	assert.eq(header.fileSize, #data, "fileSize didn't match")	-- when does size not equal #data?

	-- do this after flipping endian if necessary
	-- [=[
	do
		local checksumEndOfs =
			ffi.offsetof(header_item, 'checksum')
			+ 4 -- ffi.sizeof(header.checksum)
		assert.eq(header.checksum, adler32(
			blob.data.v + checksumEndOfs,
			#blob.data - checksumEndOfs
		))
	end
	--]=]
	-- [=[
	do
		local sha1str = ffi.string(header.sha1sig, 20)
		local sha1EndOfs = ffi.offsetof(header_item, 'sha1sig')
			+ ffi.sizeof(header.sha1sig)
		local sha1check = sha2.sha1(ffi.string(
			blob.data.v + sha1EndOfs,
			#blob.data - sha1EndOfs
		))
--DEBUG:print('sha1check', sha1check)
		assert.len(sha1check, 40)
		sha1check = string.unhex(sha1check)
		assert.type(sha1check, 'string')
		assert.len(sha1check, 20)
		assert.eq(sha1check, sha1str)
	end
	--]=]

	if header.numLinks ~= 0 then
io.stderr:write('TODO support dynamically-linked .dex files\n')
	end

--DEBUG:print('map ofs', header.mapOfs)
--DEBUG:print('stringId count', header.numStrings, 'ofs', header.stringOfsOfs)
--DEBUG:print('typeId count', header.numTypes,'ofs', header.typeOfs)
--DEBUG:print('protoId count', header.numProtos,'ofs', header.protoOfs)
--DEBUG:print('fieldId count', header.numFields,'ofs', header.fieldOfs)
--DEBUG:print('methodId count', header.numMethods,'ofs', header.methodOfs)
--DEBUG:print('classDef count', header.numClasses,'ofs', header.classOfs)
--DEBUG:print('datas size', header.dataSize, 'ofs', header.datasOfs)

	-- header is done, read structures

	local types = table()
	self.types = types


	-- destroys blobs.ofs
	local function readTypeList(ofs)
		if ofs == 0 then return end
		blob.ofs = ofs
		local numArgs = blob:readu4()
--DEBUG:print('read type list #args', numArgs)
		if numArgs == 0 then return end
		local args = table()
		for i=0,numArgs-1 do
			local typeIndex = blob:readu2()
			args[i+1] = assert.index(types, 1+typeIndex)
--DEBUG:print('read type list arg['..i..'] = '..typeIndex, args[i+1])
		end
		return args
	end


	-- wait is this redundant to the subsequent structures?
	-- or is this the equivalent of the old "constants" table in .class files?
	-- it's redundant.
	-- "This is a list of the entire contents of a file, in order."
	-- "Additionally, the map entries must be ordered by initial offset and must not overlap."
	-- Does one of those two statements imply it is supposed to be sorted by type?  Because the one that android is spitting out is not sorted by type...
	if header.mapOfs ~= 0 then
		blob.ofs = header.mapOfs
		local count = blob:readu4()
		local mapItems = ffi.cast(map_item_ptr, blob.data.v + blob.ofs)
		self.map = table()
		for i=0,count-1 do
			local map = {}
			local entry = mapItems[i]
--DEBUG:print('map src '..i..' = '..entry)
			if endianFlipped then flipEndianStruct(entry) end
			map.type = assert.index(mapListTypes, entry.typeIndex)
			map.count = entry.count
			map.offset = entry.offset
			self.map:insert(map)
--DEBUG:print('map['..i..'] = '..require 'ext.tolua'(map))
		end
	end

	-- string offset points to a list of uint32_t's which point to the string data
	-- ... which start with a uleb128 prefix
	assert.le(0, header.stringOfsOfs)
	assert.le(header.stringOfsOfs + ffi.sizeof'uint32_t' * header.numStrings, header.fileSize)
	local strings = table()
	self.strings = strings
	local stringOfsPtr = ffi.cast('uint32_t*', blob.data.v + header.stringOfsOfs)
	for i=0,header.numStrings-1 do
--DEBUG:print('header.stringOfsOfs', blob.ofs)
		blob.ofs = stringOfsPtr[i]
--DEBUG:print('stringOfs', blob.ofs)
		if blob.ofs < 0 or blob.ofs >= header.fileSize then
			error("string has bad ofs: 0x"..string.hex(blob.ofs))
		end
		local len = blob:readUleb128()
		local str = blob:readString(len)
		strings[i+1] = str
--DEBUG:print('string['..i..'] = '..require 'ext.tolua'(str))
	end

	assert.le(0, header.typeOfs)
	assert.le(header.typeOfs + ffi.sizeof'uint32_t' * header.numTypes, header.fileSize)
	local typePtr = ffi.cast('uint32_t*', blob.data.v + header.typeOfs)
	for i=0,header.numTypes-1 do
		types[i+1] = assert.index(strings, typePtr[i]+1)
--DEBUG:print('type['..i..'] = '..types[i+1])
	end

	assert.le(0, header.protoOfs)
	assert.le(header.protoOfs + ffi.sizeof(proto_id_item) * header.numProtos, header.fileSize)
	local protoPtr = ffi.cast(proto_id_item_ptr, blob.data.v + header.protoOfs)
	local protos = table()
	self.protos = protos
	for i=0,header.numProtos-1 do
		local proto = {}
		local entry = protoPtr[i]
		if endianFlipped then flipEndianStruct(entry) end
		-- I don't get ShortyDescritpor ... is it redundant to returnType + args?
--DEBUG:print('read proto shortyIndex', entry.shortyIndex)
		local shorty = assert.index(strings, 1 + entry.shortyIndex)
--DEBUG:print('read proto returnTypeIndex', entry.returnTypeIndex)
		local returnType = assert.index(types, 1 + entry.returnTypeIndex)

--DEBUG:print('read proto argTypeListOfs', entry.argTypeListOfs)
		local argTypes = readTypeList(entry.argTypeListOfs)

		-- sig but in .class format:
		local sig = '('..(argTypes and argTypes:concat() or '')..')'..returnType
		protos[i+1] = sig

--DEBUG:print('proto['..i..'] = '..require 'ext.tolua'(protos[i+1]))
	end

	assert.le(0, header.fieldOfs)
	assert.le(header.fieldOfs + ffi.sizeof(field_id_item) * header.numFields, header.fileSize)
	local fieldPtr = ffi.cast(field_id_item_ptr, blob.data.v + header.fieldOfs)
	self.fields = table()
	for i=0,header.numFields-1 do
		local field = {}
		self.fields[i+1] = field
		local entry = fieldPtr[i]
		if endianFlipped then flipEndianStruct(entry) end
		field.class = assert.index(types, 1 + entry.classIndex)
		field.sig = assert.index(types, 1 + entry.sigIndex)
		field.name = assert.index(strings, 1 + entry.nameIndex)
	end

	assert.le(0, header.methodOfs)
	assert.le(header.methodOfs + 2*ffi.sizeof'uint32_t' * header.numMethods, header.fileSize)
	local methodPtr = ffi.cast(method_id_item_ptr, blob.data.v + header.methodOfs)
	self.methods = table()
	for i=0,header.numMethods-1 do
		local method = {}
		local entry = methodPtr[i]
		if endianFlipped then flipEndianStruct(entry) end
--DEBUG:print('read method', entry)
		self.methods[i+1] = method
		method.class = assert.index(types, 1 + entry.classIndex)
		method.sig = deepCopy(assert.index(protos, 1 + entry.sigIndex))
		method.name = assert.index(strings, 1 + entry.nameIndex)
--DEBUG:print('read method['..i..'] = '..require 'ext.tolua'(method))
	end

	-- so this is interesting
	-- an ASMDex file can be more than one class
	-- oh well, as long as there's one ASMDex per DexLoader or whatever
	assert.le(0, header.classOfs)
	assert.le(header.classOfs + ffi.sizeof(class_def_item) * header.numClasses, header.fileSize)
	local classPtr = ffi.cast(class_def_item_ptr, blob.data.v + header.classOfs)
	self.classes = table()
--DEBUG:print('read classOfs', header.classOfs)
	for i=0,header.numClasses-1 do
		local class = {}
		self.classes[i+1] = class
		local entry = classPtr[i]
		if endianFlipped then flipEndianStruct(entry) end
--DEBUG:print('read class', entry)
		class.thisClass = assert.index(types, 1 + entry.thisClassIndex)
		setFlagsToObj(class, entry.accessFlags, classAccessFlags)
		class.superClass = assert.index(types, 1 + entry.superClassIndex)
		if entry.sourceFileIndex ~= NO_INDEX then
			class.sourceFile = assert.index(strings, 1 + entry.sourceFileIndex)
		end

		-- done reading classdef, read its properties:

		if entry.interfacesOfs ~= 0 then
			class.interfaces = readTypeList(entry.interfacesOfs)
		end

		if entry.annotationsOfs ~= 0 then
			io.stderr:write'!!! TODO !!! annotationsOfs\n'
		end

		if entry.classDataOfs ~= 0 then
			blob.ofs = entry.classDataOfs
--DEBUG:print('reading class data offset from 0x'..bit.tohex(blob.ofs, 8))
			local numStaticFields = blob:readUleb128()
			local numInstanceFields = blob:readUleb128()
			local numDirectMethods = blob:readUleb128()
			local numVirtualMethods = blob:readUleb128()

			local function readFields(count, isStatic)
				local fieldIndex = 0
				for i=0,count-1 do
					fieldIndex = fieldIndex + blob:readUleb128()
					local field = assert.index(self.fields, 1 + fieldIndex)
					setFlagsToObj(field, blob:readUleb128(), fieldAccessFlags)
					-- are all fields in 'numStaticFields' guaranteed to have 'isStatic' set?
					assert.eq(not not isStatic, not not field.isStatic)
				end
			end
			readFields(numStaticFields, true)
			readFields(numInstanceFields)

			local function readMethods(count, isDirect)
				local methodIndex = 0
				for i=0,count-1 do
--DEBUG:local methodStartOfs = blob.ofs
					local delta = blob:readUleb128()
					methodIndex = methodIndex + delta
--DEBUG:print('read class data methodIndex delta', delta, 'index', methodIndex)
					local method = assert.index(self.methods, 1 + methodIndex)
--DEBUG:print('reading method data', method.class, method.name, method.sig, 'from ofs 0x'..bit.tohex(methodStartOfs, 8))
					setFlagsToObj(method, blob:readUleb128(), methodAccessFlags)

					-- if isDirect then methods should have isStatic, isPrivate, or isConstructor
					assert.eq(not not isDirect, not not (method.isStatic or method.isPrivate or method.isConstructor))

					local codeOfs = blob:readUleb128()
					assert.le(0, codeOfs)
					assert.lt(codeOfs, header.fileSize)

					if codeOfs ~= 0 then
						local push = blob.ofs	-- save for later since we're in the middle of decoding classDataOfs
--DEBUG:print('reading code for method', methodIndex)
						blob.ofs = codeOfs
						local codeItem = blob:read(code_item)
--DEBUG:print('method codeItem ', codeItem)

						-- read code
						method.maxRegs = codeItem.maxRegs	-- same as "maxLocals" but for registers?
						method.regsIn = codeItem.regsIn
						method.regsOut = codeItem.regsOut
						local numTries = codeItem.numTries
						local debugInfoOfs = codeItem.debugInfoOfs
						-- codeItem.instSize is "in 16-bit code units..." ... this is the number of uint16_t's
						local instEndOfs = blob.ofs + bit.lshift(codeItem.instSize, 1)
-- me double-checking that my re-encoding of asm is correct...
method.codeData = string.bytes(ffi.string(blob.data.v + blob.ofs, bit.lshift(codeItem.instSize, 1)))
						local code = table()
						method.code = code
						while blob.ofs < instEndOfs do
--DEBUG:io.write(bit.tohex(blob.ofs, 8), ':\t')
							-- Is uint16 instruction order influenced by endian order?
							-- "Also, if this happens to be in an endian-swapped file, then the swapping is only done on individual ushort instances and not on the larger internal structures."
							-- ...whatever that means. "Sometimes." smh.
							-- is the opcode hi and lo swapped as well????
							local op = blob:readu2()
							local lo = bit.band(0xff, op)
							local hi = bit.rshift(op, 8)
							local instrClass = assert.index(InstrClassesForOp, lo)
							local inst = setmetatable({}, instrClass)
							inst:insert(inst.name)
							inst:read(hi, blob, self)
--DEBUG:print(table.mapi(inst, function(s) return tostring(s) end):concat' ')
							code:insert(inst)
						end
						assert.eq(blob.ofs, instEndOfs, "instruction decoding failed to end at the correct location (current offset vs desired)")

						if bit.band(3, blob.ofs) == 2 then blob:readu2() end	-- optional padding to be 4-byte aligned
						assert.eq(bit.band(3, blob.ofs), 0, "blob ofs supposed to be 4-byte aligned")

--DEBUG:print('method.numTries', numTries)
						if numTries > 0 then
							assert(not method.tries)
							method.tries = table()
							local lasttry
							for j=0,numTries-1 do
								-- read tries
								local try = {}
								method.tries:insert(try)

								-- "The address is a count of 16-bit code units to the start of the first covered instruction."
								--  so does that mean they are indexes into the insns[] table, or are they byte offsets, or are they file offsets?
								local trysrc = blob:read(try_item)
								try.startAddr = trysrc.startAddr
								try.instSize = trysrc.instSize
								try.handlerOfs = trysrc.handlerOfs
--DEBUG:print('got try #'..j..':', require 'ext.tolua'(try))
								-- "Elements of the array must be non-overlapping in range and in order from low to high address. "
								if lasttry then
									assert.le(lasttry.startAddr + bit.lshift(lasttry.instSize, 1), try.startAddr, "try begins after previous try ends")
								end
								assert.le(try.startAddr + bit.lshift(try.instSize, 1), codeItem.instSize, "try extends past file size")
								lasttry = try
							end
						end

						local encodedCatchHandlerListOfs = blob.ofs

						-- now we're at the end of the code structure
						-- then next is handlers which the tries have offsets into
						-- so now translate tries.handlerOfs into tries.handlers
						if method.tries then
							for tryIndex,try in ipairs(method.tries) do
--DEBUG:print('in method try', tryIndex)
								blob.ofs = encodedCatchHandlerListOfs + try.handlerOfs
								try.handlerOfs = nil
								local encodedCatchHandlerSize = blob:readSleb128()
--DEBUG:print('encodedCatchHandlerSize', encodedCatchHandlerSize)
								for j=0,math.abs(encodedCatchHandlerSize)-1 do
									local addrPair = {}
									local addrType = blob:readUleb128()
									addrPair.type = assert.index(types, 1 + addrType)
									addrPair.addr = blob:readUleb128()
--DEBUG:print('addrPair', require 'ext.tolua'(addrPair))
									table.insert(try, addrPair)
								end
								if encodedCatchHandlerSize <= 0 then
									try.catchAllAddr = blob:readUleb128()
--DEBUG:print('try.catchAllAddr', try.catchAllAddr)
								end
							end
						end

						if debugInfoOfs ~= 0 then
io.stderr:write('!!! TODO !!! debugInfoOfs '..debugInfoOfs..'\n')
						end

						blob.ofs = push
					end
				end
			end
--DEBUG:print('numDirectMethods', numDirectMethods)
--DEBUG:print('numVirtualMethods', numVirtualMethods)
			readMethods(numDirectMethods, true)
			readMethods(numVirtualMethods)
		end

		if entry.staticValuesOfs ~= 0 then
			io.stderr:write'TODO staticValuesOfs\n'
		end

--DEBUG:print('class['..i..'] = '..require 'ext.tolua'(class))
	end

	-- remove field and method references that don't belong to any defined class
	for i=#self.fields,1,-1 do
		local field = self.fields[i]
		if not self.classes:find(nil, function(cl)
			return cl.thisClass == field.class
		end) then
			self.fields:remove(i)
		end
	end
	for i=#self.methods,1,-1 do
		local method = self.methods[i]
		if not self.classes:find(nil, function(cl)
			return cl.thisClass == method.class
		end) then
			self.methods:remove(i)
		end
	end

--[[
	for i,field in ipairs(self.fields) do
		print('field['..(i-1)..'] = '..require 'ext.tolua'(field))
	end
	for i,method in ipairs(self.methods) do
		print('method['..(i-1)..'] = '..require 'ext.tolua'(method))
	end
--]]

	-- if we are in a one-class file then merge classes[1] with root and remove .class from all fields and methods (cuz its redundant anwaysy)
	if #self.classes == 1 then
		local classname = self.classes[1].thisClass
		for _,field in ipairs(self.fields) do
			assert.eq(field.class, classname)
			field.class = nil
		end
		for _,method in ipairs(self.methods) do
			assert.eq(method.class, classname)
			method.class = nil
		end
	end

	-- [[ convert self.thisClass from dex's L...; to just ...
	-- to make the args match up with ASMClass
	for _,class in ipairs(self.classes) do
		class.thisClass = toDotSepName(class.thisClass)
		class.superClass = toDotSepName(class.superClass)
		if class.interfaces then
			for i=1,#class.interfaces do
				class.interfaces[i] = toDotSepName(class.interfaces[i])
			end
		end
	end
	--]]

	-- now that names are fixed,
	-- if there is just 1 class then merge it into the base
	-- (to match up with ASMClass structure)
	if #self.classes == 1 then
		for k,v in pairs(self.classes[1]) do
			self[k] = v
		end
		self.classes = nil
	end

	-- convert field signatures to dot
	for _,field in ipairs(self.fields) do
		field.sig = toDotSepName(field.sig)
	end
	-- convert method signatures to arg table
	for _,method in ipairs(self.methods) do
		method.sig = sigStrToObj(method.sig)
	end

	--[[ these are now baked into instructions, no longer needed
	-- but keep them around for debugging
	self.protos = nil
	self.strings = nil
	self.types = nil
	self.map = nil
	--]]

	-- and at this point our .dex structure will match our .class structure
end

-------------------------------- WRITING --------------------------------

function JavaASMDex:compile()
	-- *) traversal fields and methods and method code
	-- *) build up a list of unique constants:
	--   *) strings
	--   *) types (-> strings)
	--   *) protos (-> types)
	--   *) classes' thisClass, superClass, sourceFile
-- TODO put asmclass class properties into a class={} table?
-- then asmdex when #classes==1 use .class, and then they'd match.
-- or just read them from root, how about that? and don't touch .asmclass
	--   *) field
	--   *) method
	--     *) method code
	-- for single-class dex files, auto-insert class into all listed fields and methods

	self.fields = self.fields or table()
	self.methods = self.methods or table()

	-- convert back from ... to L...;
	-- to make the args match up with asmclass
	for _,field in ipairs(self.fields) do
		field.sig = getJNISig(field.sig)
	end
	for _,method in ipairs(self.methods) do
		method.sig = getJNISig(method.sig)
	end

	-- move any class properties from root into a new class object
	-- (but only if there's no .classes already
	local buildingSingleClass
	if not self.classes then
		buildingSingleClass = true
		local class = {
			sourceFile = self.sourceFile,
			thisClass = self.thisClass,
			superClass = self.superClass,
			interfaces = self.interfaces,
		}
		for k,v in pairs(classAccessFlags) do
			class[k] = self[k]
			--self[k] = nil
		end
		self.classes = table{class}
	end

	-- [[ now convert dot names to L...; names
	for _,class in ipairs(self.classes) do
		class.thisClass = toLSlashSepSemName(class.thisClass)
		class.superClass = toLSlashSepSemName(class.superClass)
		if class.interfaces then
			for i=1,#class.interfaces do
				class.interfaces[i] = toLSlashSepSemName(class.interfaces[i])
			end
		end
	end
	--]]

	if buildingSingleClass then
		for _,field in ipairs(self.fields) do
			field.class = self.classes[1].thisClass
		end
		for _,method in ipairs(self.methods) do
			method.class = self.classes[1].thisClass
		end
	end

	-- should I do this, or require the caller to do it?
	-- auto-detect <init> and <clinit>
	for _,method in ipairs(self.methods) do
		if method.name == '<init>' then
			method.isConstructor = true
			method.isStatic = false
		end
		if method.name == '<clinit>' then
			method.isConstructor = true
			method.isStatic = true
		end
	end



	self.map = table()
	self.map:insert{type='header_item', count=1, offset=0}

	-- ok now all constants are accounted for ... start writing
	local blob = WriteBlobLE()

	local function align(n)
		blob:writeString(('\0'):rep((n - (#blob % n)) % n))
	end

	-- write header here, come back later and change it over and over again, because Google
	blob:write(header_item{
		magic = "dex\n",
		version = 0x393330,
		-- skip checksum
		-- skip sha1sig
		-- skip fileSize
		headerSize = ffi.sizeof(header_item),
		endianTag = 0x12345678,
	})


	-------- alright now we accumulate unique tables that we must later sort,
	-- we build tables one at a time i guess to keep ourselves from needing to go back and modify references once we sort tables ...

	-- just returns the index, nil if fails
	local function findUnique(arr, data)
		local index = table.find(arr, data)
		if index then return index-1 end
		return nil, "failed to find"
	end

	-- return 0-based index into our list of unique values
	local function addUnique(arr, data)
		local index = findUnique(arr, data)
		if index then return index end
		arr:insert(data)
		return #arr-1
	end

	local function traverse(visit)
		-- traverse fields for strings ...
		for _,field in ipairs(self.fields) do
			visit:field(field.class, field.name, field.sig)
		end

		-- traverse methods for strings
		for _,method in ipairs(self.methods) do
			visit:method(method.class, method.name, method.sig)
			if method.code then
				for _,inst in ipairs(method.code) do
					local lo = assert.index(opForInstName, inst[1])
					local instrClass = assert.index(InstrClassesForOp, lo)
					setmetatable(inst, instrClass)
					inst:traverse(visit)
				end
			end
			if method.tries then
				for _,try in ipairs(method.tries) do
					for _,addrPair in ipairs(try) do
						visit:type(addrPair.type)
					end
				end
			end
		end

		for _,class in ipairs(self.classes) do
			visit:type(class.thisClass)
			visit:type(class.superClass)
			visit:typelist(class.interfaces)
			if class.sourceFile then
				visit:string(class.sourceFile)
			end
		end
	end

	-- define this before traverser
	local protoPropsForSig = {}
	-- traverse from each type's table into its nested tables etc
	local function nothing() end
	local traverser = {
		string = nothing,	-- end-point, does nothing
		type = function(visit, typestr)
			visit:string(typestr)
		end,
		typelist = function(visit, typeStrs)
			if typeStrs then
				for _,typeStr in ipairs(typeStrs) do
					visit:type(typeStr)
				end
			end
		end,
		proto = function(visit, sigstr)
			local protoProps = protoPropsForSig[sigstr]
			visit:string(protoProps.shorty)
			visit:type(protoProps.returnType)
			visit:typelist(protoProps.argTypes)
		end,
		field = function(visit, class, name, sig)
			visit:type(class)
			visit:string(name)
			visit:type(sig)
		end,
		method = function(visit, class, name, sig)
			visit:type(class)
			visit:string(name)
			visit:proto(sig)
		end,

	}

	-------- prelim traversal:
	-- map prototype signatures to cached tables of their members
	-- so I don't have to parse them over and over again
	traverse(table.union({}, traverser, {
		type = nothing,
		typelist = nothing,
		proto = function(visit, sigstr)
			local protoProps = protoPropsForSig[sigstr]
			if protoProps then return end

			local sig = splitMethodJNISig(sigstr)
			if not sig then error("failed to convert sigstr "..sigstr) end

			protoProps = {}
			protoProps.shorty = sig:mapi(function(sigi)
				return #sigi > 1 and 'L' or sigi
			end):concat()
			protoProps.returnType = sig:remove(1)
			protoProps.argTypes = sig
			protoPropsForSig[sigstr] = protoProps
		end,
	}))

	-------- first we accumulate our unique strings

	local strings = table()
	-- now override traverser fields one at a time as we process each type ... and sort it ... and maybe write it ...
	traverser.string = function(visit, str)
		addUnique(strings, assert.type(str, 'string'))
	end
	traverse(traverser)

	-- sort strings for no reason except to jump through hoops Google added
	strings:sort()

	-- might as well write them out, they aren't going anywhere
	if #strings > 0 then
		align(4)
		-- fill in the string-offset-to-offsets location ... which is redundantly the header size as well ...
		local header = ffi.cast(header_item_ptr, blob.data.v)
		header.numStrings = #strings
		header.stringOfsOfs = #blob
		self.map:insert{type='string_id_item', offset=#blob, count=#strings}
		-- after header comes string_id_list ... i'm guessing that means first the offsets to string data, next the string data itself?
		-- looks like from the dex file i'm reading that the offsets-to-offsets come first,
		--  then the offsets to string data comes much much later in the file.
		--  maybe in the "support data" section?
		-- write placeholders for offsets,
		-- fill them in later when we write the string data
		for i=0,#strings-1 do
			blob:writeu4(0)
		end
	end

	local function findString(s)
		return assert(findUnique(strings, s))
	end
	self.findString = findString

	-------- next we build our types, and ignore strings

	local types = table()
	traverser.string = nothing	-- done for now
	traverser.type = function(visit, typestr)
		local index = addUnique(types, findString(typestr))
	end
	traverse(traverser)

	types:sort()	-- sort because Google

	-- fill in the type offsets
	if #types > 0 then
		align(4)
		local header = ffi.cast(header_item_ptr, blob.data.v)
		header.numTypes = #types
		header.typeOfs = #blob
		self.map:insert{type='type_id_item', offset=#blob, count=#types}
		for i,stringIndex in ipairs(types) do
			blob:writeu4(stringIndex)
		end
	end

	local function findType(typestr)
		local typeStrIndex = findString(typestr)
		return findUnique(types, typeStrIndex)
	end
	self.findType = findType

	-------- now build type lists, ignore types and strings

	local function encodeTypeList(typeStrs)
		local w = WriteBlobLE()
		w:writeu4(#typeStrs)
		for _,typeStr in ipairs(typeStrs) do
			w:writeu2(findType(typeStr))
		end
		return w:compile()
	end

	local typeLists = table()
	traverser.type = nothing	-- done for now
	traverser.typelist = function(visit, typeStrs)
		-- add as a blob, I think its safe, I think I wont have to later come back and modify its contents
		if not typeStrs then return end
		if #typeStrs == 0 then return end
		addUnique(typeLists, encodeTypeList(typeStrs))
	end
	traverse(traverser)

	-- now sort type lists by ....... ?
	typeLists:sort(function(a,b)
		local pa = ffi.cast('uint8_t*', a)
		local pb = ffi.cast('uint8_t*', b)
		local na = #a
		local nb = #b
		-- first by its uint16 typeid elements?
		for i=4,math.min(na, nb)-1,2 do
			local sa = ffi.cast('uint16_t*', pa + i)[0]
			local sb = ffi.cast('uint16_t*', pb + i)[0]
			if sa ~= sb then return sa < sb end
		end
		-- next by its length
		return na < nb
	end)

	-- 1-based except for nil/empty lists are 0
	-- return as an index for now, convert to offset later.
	local function findTypeList(typeStrs)
		if not typeStrs then return 0 end
		if #typeStrs == 0 then return 0 end
		return 1+findUnique(typeLists, encodeTypeList(typeStrs))
	end

	-- BUT DONT WRITE THEM YET WHAT WERE YOU THINKING YOU IDIOT, DID YOU THINK THE PEOPLE AT GOOGLE HAD ANY COMMON SENSE, THEY DONT!
	-- no, we gotta put it aside and put it in the "data" section later.

	-------- now build the prototypes.
	-- maybe I can do this in the same pass as the type lists?

	local function encodeProtoType(sigstr)
		local protoProps = protoPropsForSig[sigstr]
		return proto_id_item{
			shortyIndex = findString(protoProps.shorty),
			returnTypeIndex = findType(protoProps.returnType),
			argTypeListOfs = findTypeList(protoProps.argTypes),
		}
	end

	local protos = table()
	traverser.typelist = nothing
	traverser.proto = function(visit, sigstr)
		addUnique(protos, encodeProtoType(sigstr))
	end
	traverse(traverser)

	protos:sort(function(a,b)
		-- "This list must be sorted in return-type (by type_id index) major order,"
		if a.returnTypeIndex ~= b.returnTypeIndex then
			return a.returnTypeIndex < b.returnTypeIndex
		end
		-- "and then by argument list (lexicographic ordering, individual arguments ordered by type_id index)."
		-- uh ... what?
		-- next I guess they are sorted by argument-lists?
		return a.argTypeListOfs < b.argTypeListOfs
	end)

	-- and write it while you're here
	-- mind you we will have to go back and modify it to update to the argTypeListOfs whereever we write that list
	-- fill in protos ... notice, proto arg lists probably go in that generic data clump
	if #protos > 0 then
		align(4)
		local header = ffi.cast(header_item_ptr, blob.data.v)
		header.numProtos = #protos
		header.protoOfs = #blob
		self.map:insert{type='proto_id_item', offset=#blob, count=#protos}
		for i,proto in ipairs(protos) do
			blob:write(proto)
		end
	end

	local function findProto(sigstr)
		return findUnique(protos, encodeProtoType(sigstr))
	end
	self.findProto = findProto

	-------- now build the fields.

	local function encodeField(class, name, sig)
		return field_id_item{
			classIndex = findType(class),
			sigIndex = findType(sig),
			nameIndex = findString(name),
		}
	end

	-- .fields is the ctor requested fields
	-- dex lumps in internal and external references all in the same structure
	-- so fieldWrites will be that
	local fieldWrites = table()
	traverser.proto = nothing
	traverser.field = function(visit, class, name, sig)
		addUnique(fieldWrites, encodeField(class, name, sig))
	end
	traverse(traverser)

	fieldWrites:sort(function(a,b)
		-- "This list must be sorted,
		--  where the defining type (by type_id index) is the major order,
		--  field name (by string_id index) is the intermediate order,
		--  and type (by type_id index) is the minor order."
		if a.classIndex ~= b.classIndex then return a.classIndex < b.classIndex end
		if a.nameIndex ~= b.nameIndex then return a.nameIndex < b.nameIndex end
		return a.sigIndex < b.sigIndex
	end)

	-- write fields
	if #fieldWrites > 0 then
		align(4)
		local header = ffi.cast(header_item_ptr, blob.data.v)
		header.numFields = #fieldWrites
		header.fieldOfs = #blob
		self.map:insert{type='field_id_item', offset=#blob, count=#fieldWrites}
		for i,field in ipairs(fieldWrites) do
			blob:write(field)
		end
	end

	local function findField(class, name, sig)
		return findUnique(fieldWrites, encodeField(class, name, sig))
	end
	self.findField = findField

	-- mapping from 1-based fieldWriteIndex to fields for later
	local fieldWritesToOrigs = {}	-- key = field write index 0-based, value = self.fields object
	for _,field in ipairs(self.fields) do
		fieldWritesToOrigs[1+findField(field.class, field.name, field.sig)] = field

		-- might as well build access flags here too
		field.accessFlags = getFlagsFromObj(field, fieldAccessFlags)
	end

	-------- now build methods

	local function encodeMethod(class, name, sig)
		return method_id_item{
			classIndex = findType(class),
			sigIndex = findProto(sig),
			nameIndex = findString(name),
		}
	end

	local methodWrites = table()
	traverser.field = nothing
	traverser.method = function(visit, class, name, sig)
		addUnique(methodWrites, encodeMethod(class, name, sig))
	end
	traverse(traverser)

	methodWrites:sort(function(a,b)
		-- "This list must be sorted,
		--  where the defining type (by type_id index) is the major order,
		--  method name (by string_id index) is the intermediate order,
		--  and method prototype (by proto_id index) is the minor order."
		if a.classIndex ~= b.classIndex then return a.classIndex < b.classIndex end
		if a.nameIndex ~= b.nameIndex then return a.nameIndex < b.nameIndex end
		return a.sigIndex < b.sigIndex
	end)

	-- fill in methods
	if #methodWrites > 0 then
		align(4)
		local header = ffi.cast(header_item_ptr, blob.data.v)
		header.numMethods = #methodWrites
		header.methodOfs = #blob
		self.map:insert{type='method_id_item', offset=#blob, count=#methodWrites}
		for i,method in ipairs(methodWrites) do
			blob:write(method)
		end
	end

	local function findMethod(class, name, sig)
		return findUnique(methodWrites, encodeMethod(class, name, sig))
	end
	self.findMethod = findMethod

	-- mapping from 1-based methodWriteIndex to methods for later
	local methodWritesToOrigs = {}
	for _,method in ipairs(self.methods) do
		methodWritesToOrigs[1+findMethod(method.class, method.name, method.sig)] = method

		-- might as well build access flags here too
		method.accessFlags = getFlagsFromObj(method, methodAccessFlags)
	end

	-------- classdefs

	-- sort ... so that super/subclasses are in order of definition.
	-- ... just assume it's already sorted.
	do
		assert.gt(#self.classes, 0) 	-- otherwise why are we here...
		local header = ffi.cast(header_item_ptr, blob.data.v)
		header.numClasses = #self.classes
		header.classOfs = #blob
		self.map:insert{type='class_def_item', offset=#blob, count=#self.classes}
		align(4)
		for _,class in ipairs(self.classes) do
			blob:write(class_def_item{
				thisClassIndex = findType(class.thisClass),
				accessFlags = getFlagsFromObj(class, classAccessFlags),
				superClassIndex = findType(class.superClass),
				interfacesOfs = findTypeList(class.interfaces),	-- remap from typelist index to offset later ...
				sourceFileIndex = class.sourceFile
					and findString(class.sourceFile)
					or NO_INDEX,
				-- ... fill in annotation-offset later
				-- ... fill in data-offset later
				-- ... fill in static-value-offset later
			})
		end
	end
	align(4)


	---------------- HEADER END, DATA BEGIN ----------------


	-- keep track of where the headers structures end
	-- and where the support data begins
	do
		local header = ffi.cast(header_item_ptr, blob.data.v)
		header.datasOfs = #blob
	end


	-------- code items
	-- per-method, pointed from class_data_item, but the rest of class_data_item comes later I guess

	-- do these have to go in some kind of order?
	-- probably in order of written methods ...
	-- at least write out code here:
	local codeItemOfs = #blob
	local codeItemCount = 0
	for methodWriteIndex,methodWrite in ipairs(methodWrites) do
		local method = methodWritesToOrigs[methodWriteIndex]
		if method
		and method.code
		then
			align(4)
			-- save codeOfs for later for class data
			method.codeOfs = #blob

			-- statics have no 'this'
			-- except <clinit> which is static|ctor which has ... something?  the class?
			-- so I guess consturctors are ctor but ~static ?
			-- and ctor-static (i.e. <clinit>) has a regsin=0 but regsout=1?
			local isStaticNonCtor = method.isStatic and not method.isConstructor

			local protoProps = protoPropsForSig[method.sig]
			local returnType = protoProps.returnType

--DEBUG:print(method.name, 'sig', require 'ext.tolua'(sig))
			method.inferredRegsIn =
				(method.isStatic and 0 or 1)
				+ (protoProps.argTypes:mapi(function(jnisigi)
						return (jnisigi == 'J' or jnisigi == 'D') and 2 or 1
					end):sum() or 0)


			-- TODO TODO
			-- this is max # used for *calls*, not for *returns*
			-- and NOTICE it should be *irrelevant* of the register indexes themselves that are used for the call,
			-- it should just be the number of registers used.
			method.inferredRegsOut = 0

			-- TODO TODO
			-- this is the max regs = regs_in plus local reg size.
			-- regs_in start after local regs
			-- and regs_in is based on the signature
			-- How can we infer this?  by subtracting the max read register from the inferred regs in?
			method.inferredMaxRegs = method.inferredRegsIn

--DEBUG:print('maxRegs vs inferred', method.maxRegs, method.inferredMaxRegs)
--DEBUG:print('regsIn vs inferred', method.regsIn, method.inferredRegsIn)
--DEBUG:print('regsOut vs inferred', method.regsOut, method.inferredRegsOut)

			-- traverse yet again,
			-- this time get the inferred max regs
			-- and build the code blob
			local cblob = WriteBlobLE()
			for _,inst in ipairs(method.code) do
				local lo = assert.index(opForInstName, inst[1])
				local instrClass = assert.index(InstrClassesForOp, lo)
				setmetatable(inst, instrClass)
				cblob:writeu1(lo)
				inst:write(cblob, self)
				method.inferredMaxRegs = math.max(method.inferredMaxRegs, inst:maxRegs())
				method.inferredRegsOut = math.max(method.inferredRegsOut, inst:regsOut())
			end
			assert.eq(0, bit.band(#cblob, 1))
			local codeData = cblob:compile()

			codeItemCount = codeItemCount + 1

			local codeItem = code_item{
				maxRegs = method.maxRegs or method.inferredMaxRegs,
				regsIn = method.regsIn or method.inferredRegsIn,
				regsOut = method.regsOut or method.inferredRegsOut,
				numTries = method.tries and #method.tries or 0,
				debugInfoOfs = 0,
				instSize = bit.rshift(#codeData, 1),	-- instructions size in uint16_t's
			}
			if endianFlipped then flipEndianStruct(codeItem) end
			blob:write(codeItem)
			blob:writeString(codeData)

			if bit.band(3, #blob) == 2 then blob:writeu2(0) end
			assert.eq(bit.band(3, #blob), 0, "#blob supposed to be 4-byte aligned")


			if method.tries then
				for _,try in ipairs(method.tries) do
					blob:writeu4(try.startAddr or 0)
					blob:writeu2(try.instSize or 0)
					try.handlerOfsOfs = #blob	-- circle back
					blob:writeu2(try.handlerOfs or 0)
				end
				local encodedCatchHandlerListOfs = #blob
				for _,try in ipairs(method.tries) do
					-- fill in try.handlerOfs
					local ptr = ffi.cast('uint16_t*', blob.data.v + try.handlerOfsOfs)
--DEBUG:local from = ptr[0]
					ptr[0] = #blob - encodedCatchHandlerListOfs
--DEBUG:print('changing try.handlerOfsOfs from', from, 'to',ptr[0])
					blob:writeSleb128(try.catchAllAddr and -#try or #try)
					for i,addrPair in ipairs(try) do
						local typeIndex = findType(addrPair.type)
						blob:writeUleb128(typeIndex)
						blob:writeUleb128(addrPair.addr)
					end
					if try.catchAllAddr then
						blob:writeUleb128(try.catchAllAddr)
					end
				end
			end
		end
	end
	if codeItemCount > 0 then
		self.map:insert{type='code_item', offset=codeItemOfs, count=codeItemCount}
	end

	-------- debug_item_info ... nah

	-------- type lists (finally)

	if #typeLists > 0 then
		align(4)
		self.map:insert{type='type_list', offset=#blob, count=#typeLists}

		local typeListOfs = table()
		for i,typeList in ipairs(typeLists) do
--DEBUG:print('writing typeList '..(i-1)..' ofs', #blob, 'data', string.hex(typeList))
			typeListOfs[i] = #blob
			blob:writeString(typeList)
			align(4)		-- must be 4-byte-aligned *between* typelist entries...
		end
		-- now replace all proto type list indexes with offsets
		for i=0,#protos-1 do
			local protoPtr = ffi.cast(
				proto_id_item_ptr,
				blob.data.v + ffi.cast(header_item_ptr, blob.data.v).protoOfs
			) + i
			if protoPtr.argTypeListOfs ~= 0 then
				protoPtr.argTypeListOfs = assert.index(typeListOfs, protoPtr.argTypeListOfs)
			end
		end
		-- now replace all class interfacesOfs typelist index with offset
		for i=0,#self.classes-1 do
			local classDefPtr = ffi.cast(
				class_def_item_ptr,
				blob.data.v
				+ ffi.cast(header_item_ptr, blob.data.v).classOfs
			) + i
			if classDefPtr.interfacesOfs ~= 0 then
				classDefPtr.interfacesOfs = assert.index(typeListOfs, classDefPtr.interfacesOfs)
			end
		end
	end

	-------- string data

	if #strings > 0 then
		align(4)
		self.map:insert{type='string_data_item', offset=#blob, count=#strings}
		for i,s in ipairs(strings) do
			-- notice this ptr could go bad after any blob:write's
			local stringOfsPtr = ffi.cast('uint32_t*',
				blob.data.v
				+ ffi.cast(header_item_ptr, blob.data.v).stringOfsOfs
			)
			stringOfsPtr[i-1] = #blob
			blob:writeUleb128(#s)
			blob:writeString(s)
			blob:writeu1(0)		-- null term all strings
		end
	end

	-------- now class_data_item

	align(4)
	local classDataOfs = #blob
	local classDataCount = 0
	for classIndex,class in ipairs(self.classes) do
		-- per-class
		-- collect all fields that are static vs instance
		local staticFieldIndexes = table()	-- 1-based
		local instanceFieldIndexes = table()	-- 1-based
		for fieldWriteIndex=1,#fieldWrites do
			local field = fieldWritesToOrigs[fieldWriteIndex]
			if field
			and field.class == class.thisClass
			and field.accessFlags
			and field.accessFlags ~= 0
			then
				if field.isStatic then
					staticFieldIndexes:insert(fieldWriteIndex)
				else
					instanceFieldIndexes:insert(fieldWriteIndex)
				end
			end
		end

		-- collect all methods that are direct vs virtual
		local directMethodIndexes = table() 	-- 1-based
		local virtualMethodIndexes = table()	-- 1-based
		for methodWriteIndex=1,#methodWrites do
			local method = methodWritesToOrigs[methodWriteIndex]
			if method
			and method.class == class.thisClass
			and (
				(method.accessFlags and method.accessFlags ~= 0)
				or (method.codeOfs and method.codeOfs ~= 0)
			) then
				if method.isStatic
				or method.isPrivate
				or method.isConstructor
				then
					directMethodIndexes:insert(methodWriteIndex)
				else
					virtualMethodIndexes:insert(methodWriteIndex)
				end
			end
		end

		if #staticFieldIndexes > 0
		or #instanceFieldIndexes > 0
		or #directMethodIndexes > 0
		or #virtualMethodIndexes > 0
		then
			classDataCount = classDataCount + 1
			-- change the class data offset to here
			local classDefPtr = ffi.cast(class_def_item_ptr,
				blob.data.v
				+ ffi.cast(header_item_ptr, blob.data.v).classOfs
			) + (classIndex-1)
			classDefPtr.classDataOfs =  #blob

			blob:writeUleb128(#staticFieldIndexes)
			blob:writeUleb128(#instanceFieldIndexes)
			blob:writeUleb128(#directMethodIndexes)
			blob:writeUleb128(#virtualMethodIndexes)

			local function writeFields(fieldWriteIndexes)
				local lastFieldWriteIndex = 1	-- from 1-based to 0-based
				for _,fieldWriteIndex in ipairs(fieldWriteIndexes) do
					blob:writeUleb128(fieldWriteIndex - lastFieldWriteIndex)
					local field = fieldWritesToOrigs[fieldWriteIndex]
					blob:writeUleb128(field.accessFlags)
					lastFieldWriteIndex = fieldWriteIndex
				end
			end
			writeFields(staticFieldIndexes)
			writeFields(instanceFieldIndexes)

			local function writeMethods(methodWriteIndexes)
				local lastMethodWriteIndex = 1	-- from 1-based to 0-based
				for _,methodWriteIndex in ipairs(methodWriteIndexes) do
--DEBUG:print('writing class data for method', methodWriteIndex-1)
					blob:writeUleb128(methodWriteIndex - lastMethodWriteIndex)
					local method = methodWritesToOrigs[methodWriteIndex]
					blob:writeUleb128(method.accessFlags)
					-- I guess this means I better already have written the code offset data
					blob:writeUleb128(method.codeOfs or 0)
					lastMethodWriteIndex = methodWriteIndex
				end
			end
			writeMethods(directMethodIndexes)
			writeMethods(virtualMethodIndexes)
		end
	end
	if classDataCount > 0 then
		self.map:insert{type='class_data_item', offset=classDataOfs, count=classDataCount}
	end

	-- the dex files I'm looking at will have a single empty entry for annotations ...
	-- ... even if every class def has annotation ofs set to 0 ...
	align(4)
	self.map:insert{type='annotation_set_item', offset=#blob, count=1}
	blob:writeu4(0)


	-- TODO link data last?


	-- only after everything, write the map data
	-- thats the order that I am seeing .dex files made
	-- but notice, this means map_item is not sorted by type_order, since map_list is midway down the type order ...
	if #self.map > 0 then	-- should always be true
		align(4)
		self.map:insert{type='map_list', offset=#blob, count=1}
		local header = ffi.cast(header_item_ptr, blob.data.v)
--DEBUG:local from = header.mapOfs
		header.mapOfs = #blob
--DEBUG:print('changing mapOfs from', from, 'to', #blob)
		blob:writeu4(#self.map)
		for _,entry in ipairs(self.map) do
			local item = map_item{
				typeIndex = assert.index(mapListTypeForName, entry.type),
				unused = 0,
				count = entry.count,
				offset = entry.offset,
			}
			if endianFlipped then flipEndianStruct(item) end
			blob:write(item)
		end
	end

	-- now the entirety of blob.data is done
	-- don't touch it anymore
	-- now we fill in header info pertaining to the whole file

	-- finally write the data section,
	-- which starts after the header's tables and ends here
	local header = ffi.cast(header_item_ptr, blob.data.v)
	header.dataSize = #blob - header.datasOfs
	header.fileSize = #blob

	-- now that header offsets are filled out and everything is done but checksums,
	-- flip header endian-ness
	if endianFlipped then flipEndianStruct(header) end

	-- now sha1 checksum TODO
	local sha1Ofs = ffi.offsetof(header_item, 'sha1sig')
	local sha1sig = sha2.sha1(ffi.string(header.sha1sig + 20, #blob - sha1Ofs - 20))
--DEBUG:print('sha1sig', sha1sig)
	assert.len(assert.type(sha1sig, 'string'), 40)
	sha1sig = string.unhex(sha1sig)
	assert.len(assert.type(sha1sig, 'string'), 20)
	ffi.copy(header.sha1sig, sha1sig, 20)

	-- now adler
	local checksumOfs = ffi.offsetof(header_item, 'checksum')
	header.checksum  = adler32(blob.data.v + checksumOfs + 4, #blob - checksumOfs - 4)
--DEBUG:print('adler32', '0x'..bit.tohex(checksum, 8))
	-- TODO remove temp write fields?

	return blob:compile()
end

return JavaASMDex
