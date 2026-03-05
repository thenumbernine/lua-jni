--[[
https://source.android.com/docs/core/runtime/dex-format
https://source.android.com/docs/core/runtime/dalvik-bytecode
https://source.android.com/docs/core/runtime/instruction-formats
--]]
local ffi = require 'ffi'
local class = require 'ext.class'
local assert = require 'ext.assert'
local table = require 'ext.table'
local string = require 'ext.string'
local ReadBlobLE = require 'java.blob'.ReadBlobLE
local WriteBlobLE = require 'java.blob'.WriteBlobLE
local deepCopy = require 'java.util'.deepCopy
local splitMethodJNISig = require 'java.util'.splitMethodJNISig
local setFlagsToObj = require 'java.util'.setFlagsToObj
local getFlagsFromObj = require 'java.util'.getFlagsFromObj
local classAccessFlags = require 'java.util'.nestedClassAccessFlags	-- dalvik's class access flags matches up with .class's nested-class access flags
local fieldAccessFlags = require 'java.util'.fieldAccessFlags
local methodAccessFlags = require 'java.util'.methodAccessFlags

local sizeOfProto = 3 * ffi.sizeof'uint32_t'
local sizeOfClass = 8 * ffi.sizeof'uint32_t'

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
		error('OOB string '..stringIndex)
	end
	inst:insert(str)
end
local function instReadString(inst, index, asm)
	return (asm.addString(inst[index]))
end

local function instPushType(inst, typeIndex, asm)
	local typ = asm.types[1+typeIndex]
	if not typ then
		error('OOB type '..typeIndex)
	end
	inst:insert(typ)
end
local function instReadType(inst, index, asm)
	return (asm.addString(inst[index]))
end

local function instPushProto(inst, protoIndex, asm)
	local proto = asm.protos[1+protoIndex]
	if not proto then
		error('OOB proto '..protoIndex)
	end
	inst:insert(proto)
end
local function instReadProto(inst, index, asm)
	return (asm.addProto(inst[index]))
end

local function instPushField(inst, fieldIndex, asm)
	local field = asm.fields[1+fieldIndex]
	if not field then
		error('OOB field '..fieldIndex)
	end
	inst:insert(field.class)
	inst:insert(field.name)
	inst:insert(field.sig)
end
local function instReadField(inst, index, asm)
	return (asm.addField(inst[index], inst[index+1], inst[index+2]))
end

local function instPushMethod(inst, methodIndex, asm)
	local method = asm.methods[1+methodIndex]
	if not method then
		error('OOB method '..methodIndex)
	end
	inst:insert(method.class)
	inst:insert(method.name)
	inst:insert(method.sig)
end
local function instReadMethod(inst, index, asm)
	if not inst[index]
	or not inst[index+1]
	or not inst[index+2]
	then
		error("instruction needs args "..index..'-'..(index+2)..': '..require'ext.tolua'(inst))
	end
	return (asm.addMethod(inst[index], inst[index+1], inst[index+2]))
end


-- TODO even bother with this, why not just read/write numbers?
local function readreg(s)
	return (assert(tonumber(s:match'^v(.*)$', 16)))
end
local function readregopt(s)
	return s and (assert(tonumber(s:match'^v(.*)$', 16))) or 0
end


local Instr = class()

local Instr10x = Instr:subclass()
function Instr10x.read(inst, hi, blob, asm)
	inst:insert(hi)				-- NOTICE throws away hi
end
function Instr10x.write(inst, blob, asm)
	blob:writeu1(inst[2] or 0)
end

local Instr12x = Instr:subclass()
function Instr12x.read(inst, hi, blob, asm)
	inst:insert('v'..bit.tohex(bit.band(hi, 0xf), 1))
	inst:insert('v'..bit.tohex(bit.band(bit.rshift(hi, 4), 0xf), 1))
end
function Instr12x.write(inst, blob, asm)
	blob:writeu1(bit.bor(
		bit.band(0xf, readreg(inst[2])),
		bit.lshift(bit.band(0xf, readreg(inst[3])), 4)
	))
end

local Instr11x = Instr:subclass()
function Instr11x.read(inst, hi, blob, asm)
	inst:insert('v'..bit.tohex(hi, 2))
end
function Instr11x.write(inst, blob, asm)
	blob:writeu1(readreg(inst[2]))
end

local Instr11n = Instr:subclass()
function Instr11n.read(inst, hi, blob, asm)
	inst:insert('v'..bit.tohex(bit.band(0xf, hi), 1))	-- A = reg (4 bits)
	inst:insert(bit.band(0xf, bit.rshift(hi, 8)))		-- B = signed 4 bit
end
function Instr11n.write(inst, blob, asm)
	blob:writeu1(bit.bor(
		bit.band(0xf, readreg(inst[2])),
		bit.lshift(bit.band(0xf, inst[3]), 4)
	))
end

local Instr10t = Instr:subclass()
function Instr10t.read(inst, hi, blob, asm)
	inst:insert(hi)					-- signed 8 bit branch offset
end
function Instr10t.write(inst, blob, asm)
	blob:writeu1(inst[2])
end

local Instr22x = Instr:subclass()
function Instr22x.read(inst, hi, blob, asm)
	inst:insert('v'..bit.tohex(hi, 2))
	inst:insert('v'..bit.tohex(blob:readu2(), 4))
end
function Instr22x.write(inst, blob, asm)
	blob:writeu1(readreg(inst[2]))
	blob:writeu2(readreg(inst[3]))
end

local Instr21s = Instr:subclass()
function Instr21s.read(inst, hi, blob, asm)
	inst:insert('v'..bit.tohex(hi, 2))
	inst:insert(blob:readu2())	-- signed
end
function Instr21s.write(inst, blob, asm)
	blob:writeu1(readreg(inst[2]))
	blob:writeu2(inst[3])
end

local Instr21h = Instr:subclass()
function Instr21h.read(inst, hi, blob, asm)
	inst:insert('v'..bit.tohex(hi, 2))
	inst:insert(blob:readu2())
end
function Instr21h.write(inst, blob, asm)
	blob:writeu1(readreg(inst[2]))
	blob:writeu2(inst[3])
end

local Instr21c_string = Instr:subclass()
function Instr21c_string.read(inst, hi, blob, asm)
	inst:insert('v'..bit.tohex(hi, 2))
	instPushString(inst, blob:readu2(), asm)
end
function Instr21c_string.write(inst, blob, asm)
	blob:writeu1(readreg(inst[2]))
	blob:writeu2(instReadString(inst, 3, asm))
end

local Instr21c_type = Instr:subclass()
function Instr21c_type.read(inst, hi, blob, asm)
	inst:insert('v'..bit.tohex(hi, 2))
	instPushType(inst, blob:readu2(), asm)
end
function Instr21c_type.write(inst, blob, asm)
	blob:writeu1(readreg(inst[2]))
	blob:writeu2(instReadType(inst, 3, asm))
end

local Instr21c_field = Instr:subclass()
function Instr21c_field.read(inst, hi, blob, asm)
	inst:insert('v'..bit.tohex(hi, 2))
	instPushField(inst, blob:readu2(), asm)
end
function Instr21c_field.write(inst, blob, asm)
	blob:writeu1(readreg(inst[2]))
	blob:writeu2(instReadField(inst, 3, asm))
end

local Instr22c_type = Instr:subclass()
function Instr22c_type.read(inst, hi, blob, asm)
	inst:insert('v'..bit.tohex(bit.band(hi, 0xf), 1))
	inst:insert('v'..bit.tohex(bit.band(bit.rshift(hi, 4), 0xf), 1))
	instPushType(inst, blob:readu2(), asm)
end
function Instr22c_type.write(inst, blob, asm)
	blob:writeu1(bit.bor(
		bit.band(0xf, readreg(inst[2])),
		bit.lshift(bit.band(0xf, readreg(inst[3])), 4)
	))
	blob:writeu2(instReadType(inst, 4, asm))
end

local Instr22c_field = Instr:subclass()
function Instr22c_field.read(inst, hi, blob, asm)
	inst:insert('v'..bit.tohex(bit.band(hi, 0xf), 1))
	inst:insert('v'..bit.tohex(bit.band(bit.rshift(hi, 4), 0xf), 1))
	instPushField(inst, blob:readu2(), asm)
end
function Instr22c_field.write(inst, blob, asm)
	blob:writeu1(bit.bor(
		bit.band(0xf, readreg(inst[2])),
		bit.lshift(bit.band(0xf, readreg(inst[3])), 4)
	))
	blob:writeu2(instReadField(inst, 4, asm))
end

local Instr23x = Instr:subclass()
function Instr23x.read(inst, hi, blob, asm)
	inst:insert('v'..bit.tohex(hi, 2))
	inst:insert('v'..bit.tohex(blob:readu1(), 2))	-- I'm sure I'm doign this wrong but it says vAA vBB vCC and that A is 8 bits and that the whole instruction reads 2 words, so *shrug* no sign of bitness of B or C
	inst:insert('v'..bit.tohex(blob:readu1(), 2))
end
function Instr23x.write(inst, blob, asm)
	blob:writeu1(readreg(inst[2]))
	blob:writeu1(readreg(inst[3]))
	blob:writeu1(readreg(inst[4]))
end

local Instr20t = Instr:subclass()
function Instr20t.read(inst, hi, blob, asm)
	inst:insert(blob:reads2())		-- signed
	inst:insert(hi)		-- NOTICE throws away hi
end
function Instr20t.write(inst, blob, asm)
	blob:writeu1(inst[3] or 0)	-- out of order, throw-away is last
	blob:writes2(inst[2])
end

local Instr22t = Instr:subclass()
function Instr22t.read(inst, hi, blob, asm)
	inst:insert('v'..bit.tohex(bit.band(hi, 0xf), 1))
	inst:insert('v'..bit.tohex(bit.band(bit.rshift(hi, 4), 0xf), 1))
	inst:insert(blob:reads2())
end
function Instr22t.write(inst, blob, asm)
	blob:writeu1(bit.bor(
		bit.band(0xf, readreg(inst[2])),
		bit.lshift(bit.band(0xf, readreg(inst[3])), 4)
	))
	blob:writes2(inst[4])
end

local Instr21t = Instr:subclass()
function Instr21t.read(inst, hi, blob, asm)
	inst:insert('v'..bit.tohex(hi, 2))
	inst:insert(blob:reads2())
end
function Instr21t.write(inst, blob, asm)
	blob:writeu1(readreg(inst[2]))
	blob:writes2(inst[3])
end

local Instr22s = Instr:subclass()
function Instr22s.read(inst, hi, blob, asm)
	inst:insert('v'..bit.tohex(bit.band(hi, 0xf), 1))
	inst:insert('v'..bit.tohex(bit.band(bit.rshift(hi, 4), 0xf), 1))
	inst:insert(blob:reads2())
end
function Instr22s.write(inst, blob, asm)
	blob:writeu1(bit.bor(
		bit.band(0xf, readreg(inst[2])),
		bit.lshift(bit.band(0xf, readreg(inst[3])), 4)
	))
	blob:writes2(inst[4])
end

local Instr22b = Instr:subclass()
function Instr22b.read(inst, hi, blob, asm)
	inst:insert('v'..bit.tohex(bit.band(hi, 0xf), 1))
	inst:insert('v'..bit.tohex(bit.band(bit.rshift(hi, 4), 0xf), 1))
	inst:insert(blob:reads2())	-- A is bits, B is 8 bits, C is 8 bits ... so C hi is unused? ... or C lo?
end
function Instr22b.write(inst, blob, asm)
	blob:writeu1(bit.bor(
		bit.band(0xf, readreg(inst[2])),
		bit.lshift(bit.band(0xf, readreg(inst[3])), 4)
	))
	blob:writes2(inst[4])
end

local Instr21c_method = Instr:subclass()
function Instr21c_method.read(inst, hi, blob, asm)
	inst:insert('v'..bit.tohex(hi, 2))
	instPushMethod(inst, blob:readu2(), asm)
end
function Instr21c_method.write(inst, blob, asm)
	blob:writeu1(readreg(inst[2]))
	blob:writeu2(instReadMethod(inst, 3, asm))
end

local Instr21c_proto = Instr:subclass()
function Instr21c_proto.read(inst, hi, blob, asm)
	inst:insert('v'..bit.tohex(hi, 2))
	instPushProto(blob:readu2())
end
function Instr21c_proto.write(inst, blob, asm)
	blob:writeu1(readreg(inst[2]))
	blob:writeu2(instReadProto(inst, 3, asm))
end

local Instr32x = Instr:subclass()
function Instr32x.read(inst, hi, blob, asm)
	inst:insert('v'..bit.tohex(blob:readu2(), 4))
	inst:insert('v'..bit.tohex(blob:readu2(), 4))
	inst:insert(hi)	-- NOTICE throws away hi
end
function Instr32x.write(inst, blob, asm)
	blob:writeu1(inst[4] or 0)
	blob:writeu2(readreg(inst[2]))
	blob:writeu2(readreg(inst[3]))
end

local Instr31i = Instr:subclass()
function Instr31i.read(inst, hi, blob, asm)
	inst:insert('v'..bit.tohex(hi, 2))
	inst:insert(blob:reads4())	-- will this be 4-byte aligned?
end
function Instr31i.write(inst, blob, asm)
	blob:writeu1(readreg(inst[2]))
	blob:writes4(inst[3])
end

local Instr31c_string = Instr:subclass()
function Instr31c_string.read(inst, hi, blob, asm)
	inst:insert('v'..bit.tohex(hi, 2))
	instPushString(inst, blob:readu4(), asm)
end
function Instr31c_string.write(inst, blob, asm)
	blob:writeu1(readreg(inst[2]))
	blob:writeu4(instReadString(inst3, 3, asm))
end

local Instr35c_type = Instr:subclass()
function Instr35c_type.read(inst, hi, blob, asm)
	local argc = bit.band(hi, 0xf)
	if argc < 1 or argc > 5 then
		error(inst[1].." expected 1-5 args, found "..argc)
	end

	local typeIndex = blob:readu2()	-- B = type
	instPushType(inst, typeIndex, asm)

	-- will the 3rd byte be read if there is only 1 argc?
	local x = blob:readu2()

	-- C..G are 4 bits each, so 20 bits total, so one of them is top nibble of 'hi' and the rest are another uint16 ...
	local regs = table{
		'v'..bit.tohex(bit.band(bit.rshift(hi, 4), 0xf), 1),
		'v'..bit.tohex(bit.band(x, 0xf), 1),
		'v'..bit.tohex(bit.band(bit.rshift(x, 4), 0xf), 1),
		'v'..bit.tohex(bit.band(bit.rshift(x, 8), 0xf), 1),
		'v'..bit.tohex(bit.band(bit.rshift(x, 12), 0xf), 1),
	}
	inst:append(regs:sub(1, argc))
end
function Instr35c_type.write(inst, blob, asm)
	local argc = #inst - 2
	if argc < 1 or argc > 5 then
		error(inst[1].." expected 1-5 args, found "..argc)
	end

	blob:writeu1(bit.bor(
		argc,
		bit.lshift(bit.band(0xf, readregopt(inst[4])), 4)
	))
	blob:writeu2(instReadType(inst, 3, asm))
	blob:writeu2(bit.bor(
		bit.band(0xf, readregopt(inst[5])),
		bit.lshift(bit.band(0xf, readregopt(inst[6])), 4),
		bit.lshift(bit.band(0xf, readregopt(inst[7])), 8),
		bit.lshift(bit.band(0xf, readregopt(inst[8])), 12)
	))
end

local Instr35c_method = Instr:subclass()
function Instr35c_method.read(inst, hi, blob, asm)
	local argc = bit.band(hi, 0xf)
	if argc < 0 or argc > 5 then
		error(inst[1].." expected 0-5 args, found "..argc)
	end

	local methodIndex = blob:readu2()	-- B = method
	instPushMethod(inst, methodIndex, asm)

	-- C..G are 4 bits each, so 20 bits total, so one of them is top nibble of 'hi' and the rest are another uint16 ...
	local x = blob:readu2()

	local regs = table{
		'v'..bit.tohex(bit.band(bit.rshift(hi, 4), 0xf), 1),
		'v'..bit.tohex(bit.band(x, 0xf), 1),
		'v'..bit.tohex(bit.band(bit.rshift(x, 4), 0xf), 1),
		'v'..bit.tohex(bit.band(bit.rshift(x, 8), 0xf), 1),
		'v'..bit.tohex(bit.band(bit.rshift(x, 12), 0xf), 1),
	}
	inst:append(regs:sub(1, argc))
end
function Instr35c_method.write(inst, blob, asm)
	local argc = #inst - 4
	if argc < 0 or argc > 5 then
		error(inst[1].." expected 0-5 args, found "..argc)
	end

	blob:writeu1(bit.bor(
		argc,
		bit.lshift(bit.band(0xf, readregopt(inst[5])), 4)
	))
	blob:writeu2(instReadMethod(inst, 2, asm))
	blob:writeu2(bit.bor(
		bit.band(0xf, readregopt(inst[6])),
		bit.lshift(bit.band(0xf, readregopt(inst[7])), 4),
		bit.lshift(bit.band(0xf, readregopt(inst[8])), 8),
		bit.lshift(bit.band(0xf, readregopt(inst[9])), 12)
	))
end

local Instr3rc_type = Instr:subclass()
function Instr3rc_type.read(inst, hi, blob, asm)
	inst:insert(hi)	-- A = array size and argument word count ... N = A + C - 1
	local typeIndex = blob:readu2()	-- B = type
	instPushType(inst, typeIndex, asm)
	inst:insert('v'..bit.tohex(blob:readu2(), 4))				-- C = first arg register
end
function Instr3rc_type.write(inst, blob, asm)
	blob:writeu1(inst[2])
	blob:writeu2(instReadType(inst, 3, asm))
	blob:writeu2(readreg(inst[4]))
end

local Instr3rc_method = Instr:subclass()
function Instr3rc_method.read(inst, hi, blob, asm)
	inst:insert('v'..bit.tohex(hi, 2))	-- A = array size and argument word count ... N = A + C - 1
	local methodIndex = blob:readu2()	-- B = method
	instPushMethod(inst, methodIndex, asm)
	inst:insert('v'..bit.tohex(blob:readu2(), 4))				-- C = first arg register
end
function Instr3rc_method.write(inst, blob, asm)
	blob:writeu1(readreg(inst[2]))
	blob:writeu2(instReadType(inst, 3, asm))
	blob:writeu2(readreg(inst[4]))
end

local Instr31t = Instr:subclass()
function Instr31t.read(inst, hi, blob, asm)
	inst:insert('v'..bit.tohex(hi, 2))
	inst:insert(blob:reads4())	-- signed branch offset to table data pseudo-instruction
end
function Instr31t.write(inst, blob, asm)
	blob:writeu1(readreg(inst[2]))
	blob:writes4(inst[3])
end

local Instr30t = Instr:subclass()
function Instr30t.read(inst, hi, blob, asm)
	inst:insert(blob:reads4())
	inst:insert(hi)	-- NOTICE hi gets thrown away
end
function Instr30t.write(inst, blob, asm)
	blob:writeu1(inst[3] or 0)
	blob:writes4(inst[2])
end

local Instr35c_callsite = Instr:subclass()
function Instr35c_callsite.read(inst, hi, blob, asm)
	-- TODO
	inst:insert(hi)
	inst:insert(blob:readu2())
	inst:insert(blob:readu2())
end
function Instr35c_callsite.write(inst, blob, asm)
	blob:writeu1(inst[2])
	blob:writeu2(inst[3])
	blob:writeu2(inst[4])
end

local Instr3rc_callsite = Instr:subclass()
function Instr3rc_callsite.read(inst, hi, blob, asm)
	-- TODO
	inst:insert(hi)
	inst:insert(blob:readu2())
	inst:insert(blob:readu2())
end
function Instr3rc_callsite.write(inst, blob, asm)
	blob:writeu1(inst[2])
	blob:writeu2(inst[3])
	blob:writeu2(inst[4])
end


local Instr45cc = Instr:subclass()
function Instr45cc.read(inst, hi, blob, asm)
	local argc = bit.band(0xf, hi)
	if argc < 1 or argc > 5 then
		error(inst[1].." expected 1-5 args, found "..argc)
	end

	local methodIndex = blob:readu2()	-- B = method (16 bits)
	instPushMethod(inst, methodIndex, asm)

	-- D E F G are arg registers
	local x = blob:readu2()
	local regs = table{
		'v'..bit.tohex(bit.rshift(bit.band(0xf, hi), 4), 1),	-- C = receiver 4 bits
		'v'..bit.tohex(bit.band(x, 0xf), 1),
		'v'..bit.tohex(bit.band(bit.rshift(x, 4), 0xf), 1),
		'v'..bit.tohex(bit.band(bit.rshift(x, 8), 0xf), 1),
		'v'..bit.tohex(bit.band(bit.rshift(x, 12), 0xf), 1),
	}
	inst:append(regs:sub(1, argc))

	local protoIndex = blob:readu2()	-- H = proto
	instPushProto(inst, protoIndex, asm)
end
function Instr45cc.write(inst, blob, asm)
	local argc = #inst - 5
	if argc < 1 or argc > 5 then
		error(inst[1].." expected 1-5 args, found "..argc)
	end

	blob:writeu1(bit.bor(
		argc,
		bit.lshift(bit.band(0xf, readregopt(inst[5])), 4)
	))

	blob:writeu2(instReadMethod(inst, 2, asm))

	blob:writeu2(bit.bor(
		bit.band(0xf, readreg(inst[6])),
		bit.lshift(bit.band(0xf, readreg(inst[7])), 4),
		bit.lshift(bit.band(0xf, readreg(inst[8])), 8),
		bit.lshift(bit.band(0xf, readreg(inst[9])), 12)
	))
	blob:writeu2(instReadProto(inst, 11, asm))
end

local Instr4rcc = Instr:subclass()
function Instr4rcc.read(inst, hi, blob, asm)
	inst:insert(hi)	-- arg word count 8 bits

	local methodIndex = blob:readu2()	-- B = method (16 bits)
	instPushMethod(inst, methodIndex, asm)

	inst:insert('v'..bit.tohex(blob:readu2(), 4))	-- C = receiver 16 bits

	local protoIndex = blob:readu2()	-- H = proto
	instPushProto(inst, protoIndex, asm)
end
function Instr4rcc.write(inst, blob, asm)
	blob:writeu1(bit.bor(
		bit.band(0xf, inst[2]),
		bit.lshift(bit.band(0xf, readreg(inst[6])), 4)
	))
	blob:writeu2(instReadMethod(inst, 3, asm))
	blob:writeu2(readreg(inst[7]))
	blob:writeu2(instReadProto(inst, 8, asm))
end

local Instr51l_double = Instr:subclass()
function Instr51l_double.read(inst, hi, blob, asm)
	inst:insert('v'..bit.tohex(hi, 2))
	inst:insert(blob:read'jdouble')
end
function Instr51l_double.write(inst, blob, asm)
	blob:writeu1(readreg(inst[2]))
	blob:write('jdouble', inst[3])
end

local instDescForOp = {
	[0x00] = Instr10x:subclass{name='nop'},					-- 00 10x	nop	 	Waste cycles.	Note: Data-bearing pseudo-instructions are tagged with this opcode, in which case the high-order byte of the opcode unit indicates the nature of the data. See "packed-switch-payload Format", "sparse-switch-payload Format", and "fill-array-data-payload Format" below.
	[0x01] = Instr12x:subclass{name='move'},					-- 01 12x	move vA, vB	A: destination register (4 bits) B: source register (4 bits)	Move the contents of one non-object register to another.
	[0x02] = Instr22x:subclass{name='move/from16'},			-- 02 22x	move/from16 vAA, vBBBB	A: destination register (8 bits) B: source register (16 bits)	Move the contents of one non-object register to another.
	[0x03] = Instr32x:subclass{name='move/16'},				-- 03 32x	move/16 vAAAA, vBBBB	A: destination register (16 bits) B: source register (16 bits)	Move the contents of one non-object register to another.
	[0x04] = Instr12x:subclass{name='move-wide'},				-- 04 12x	move-wide vA, vB	A: destination register pair (4 bits) B: source register pair (4 bits)	Move the contents of one register-pair to another. Note: It is legal to move from vN to either vN-1 or vN+1, so implementations must arrange for both halves of a register pair to be read before anything is written.
	[0x05] = Instr22x:subclass{name='move-wide/from16'},		-- 05 22x	move-wide/from16 vAA, vBBBB	A: destination register pair (8 bits) B: source register pair (16 bits)	Move the contents of one register-pair to another. Note: Implementation considerations are the same as move-wide, above.
	[0x06] = Instr32x:subclass{name='move-wide/16'},			-- 06 32x	move-wide/16 vAAAA, vBBBB	A: destination register pair (16 bits) B: source register pair (16 bits)	Move the contents of one register-pair to another. Note: Implementation considerations are the same as move-wide, above.
	[0x07] = Instr12x:subclass{name='move-object'},			-- 07 12x	move-object vA, vB	A: destination register (4 bits) B: source register (4 bits)	Move the contents of one object-bearing register to another.
	[0x08] = Instr22x:subclass{name='move-object/from16'},		-- 08 22x	move-object/from16 vAA, vBBBB	A: destination register (8 bits) B: source register (16 bits)	Move the contents of one object-bearing register to another.
	[0x09] = Instr32x:subclass{name='move-object/16'},			-- 09 32x	move-object/16 vAAAA, vBBBB	A: destination register (16 bits) B: source register (16 bits)	Move the contents of one object-bearing register to another.
	[0x0a] = Instr11x:subclass{name='move-result'},			-- 0a 11x	move-result vAA	A: destination register (8 bits)	Move the single-word non-object result of the most recent invoke-kind into the indicated register. This must be done as the instruction immediately after an invoke-kind whose (single-word, non-object) result is not to be ignored; anywhere else is invalid.
	[0x0b] = Instr11x:subclass{name='move-result-wide'},			-- 0b 11x	move-result-wide vAA	A: destination register pair (8 bits)	Move the double-word result of the most recent invoke-kind into the indicated register pair. This must be done as the instruction immediately after an invoke-kind whose (double-word) result is not to be ignored; anywhere else is invalid.
	[0x0c] = Instr11x:subclass{name='move-result-object'},			-- 0c 11x	move-result-object vAA	A: destination register (8 bits)	Move the object result of the most recent invoke-kind into the indicated register. This must be done as the instruction immediately after an invoke-kind or filled-new-array whose (object) result is not to be ignored; anywhere else is invalid.
	[0x0d] = Instr11x:subclass{name='move-exception'},			-- 0d 11x	move-exception vAA	A: destination register (8 bits)	Save a just-caught exception into the given register. This must be the first instruction of any exception handler whose caught exception is not to be ignored, and this instruction must only ever occur as the first instruction of an exception handler; anywhere else is invalid.
	[0x0e] = Instr10x:subclass{name='return-void'},			-- 0e 10x	return-void	 	Return from a void method.
	[0x0f] = Instr11x:subclass{name='return'},			-- 0f 11x	return vAA	A: return value register (8 bits)	Return from a single-width (32-bit) non-object value-returning method.
	[0x10] = Instr11x:subclass{name='return-wide'},			-- 10 11x	return-wide vAA	A: return value register-pair (8 bits)	Return from a double-width (64-bit) value-returning method.
	[0x11] = Instr11x:subclass{name='return-object'},			-- 11 11x	return-object vAA	A: return value register (8 bits)	Return from an object-returning method.
	[0x12] = Instr11n:subclass{name='const/4'},			-- 12 11n	const/4 vA, #+B	A: destination register (4 bits) B: signed int (4 bits)	Move the given literal value (sign-extended to 32 bits) into the specified register.
	[0x13] = Instr21s:subclass{name='const/16'},			-- 13 21s	const/16 vAA, #+BBBB	A: destination register (8 bits) B: signed int (16 bits)	Move the given literal value (sign-extended to 32 bits) into the specified register.
	[0x14] = Instr31i:subclass{name='const'},			-- 14 31i	const vAA, #+BBBBBBBB	A: destination register (8 bits) B: arbitrary 32-bit constant	Move the given literal value into the specified register.
	[0x15] = Instr21h:subclass{name='const/high16'},			-- 15 21h	const/high16 vAA, #+BBBB0000	A: destination register (8 bits) B: signed int (16 bits)	Move the given literal value (right-zero-extended to 32 bits) into the specified register.
	[0x16] = Instr21s:subclass{name='const-wide/16'},			-- 16 21s	const-wide/16 vAA, #+BBBB	A: destination register (8 bits) B: signed int (16 bits)	Move the given literal value (sign-extended to 64 bits) into the specified register-pair.
	[0x17] = Instr31i:subclass{name='const-wide/32'},			-- 17 31i	const-wide/32 vAA, #+BBBBBBBB	A: destination register (8 bits) B: signed int (32 bits)	Move the given literal value (sign-extended to 64 bits) into the specified register-pair.
	[0x18] = Instr51l_double:subclass{name='const-wide'},			-- 18 51l	const-wide vAA, #+BBBBBBBBBBBBBBBB	A: destination register (8 bits) B: arbitrary double-width (64-bit) constant	Move the given literal value into the specified register-pair.
	[0x19] = Instr21h:subclass{name='const-wide/high16'},			-- 19 21h	const-wide/high16 vAA, #+BBBB000000000000	A: destination register (8 bits) B: signed int (16 bits)	Move the given literal value (right-zero-extended to 64 bits) into the specified register-pair.
	[0x1a] = Instr21c_string:subclass{name='const-string'},			-- 1a 21c	const-string vAA, string@BBBB	A: destination register (8 bits) B: string index	Move a reference to the string specified by the given index into the specified register.
	[0x1b] = Instr31c_string:subclass{name='const-string/jumbo'},			-- 1b 31c	const-string/jumbo vAA, string@BBBBBBBB	A: destination register (8 bits) B: string index	Move a reference to the string specified by the given index into the specified register.
	[0x1c] = Instr21c_type:subclass{name='const-class'},			-- 1c 21c	const-class vAA, type@BBBB	A: destination register (8 bits) B: type index	Move a reference to the class specified by the given index into the specified register. In the case where the indicated type is primitive, this will store a reference to the primitive type's degenerate class.
	[0x1d] = Instr11x:subclass{name='monitor-enter'},			-- 1d 11x	monitor-enter vAA	A: reference-bearing register (8 bits)	Acquire the monitor for the indicated object.
	[0x1e] = Instr11x:subclass{name='monitor-exit'},			-- 1e 11x	monitor-exit vAA	A: reference-bearing register (8 bits)	Release the monitor for the indicated object. Note: If this instruction needs to throw an exception, it must do so as if the pc has already advanced past the instruction. It may be useful to think of this as the instruction successfully executing (in a sense), and the exception getting thrown after the instruction but before the next one gets a chance to run. This definition makes it possible for a method to use a monitor cleanup catch-all (e.g., finally) block as the monitor cleanup for that block itself, as a way to handle the arbitrary exceptions that might get thrown due to the historical implementation of Thread.stop(), while still managing to have proper monitor hygiene.
	[0x1f] = Instr21c_type:subclass{name='check-cast'},			-- 1f 21c	check-cast vAA, type@BBBB	A: reference-bearing register (8 bits) B: type index (16 bits)	Throw a ClassCastException if the reference in the given register cannot be cast to the indicated type. Note: Since A must always be a reference (and not a primitive value), this will necessarily fail at runtime (that is, it will throw an exception) if B refers to a primitive type.
	[0x20] = Instr22c_type:subclass{name='instance-of'},			-- 20 22c	instance-of vA, vB, type@CCCC	A: destination register (4 bits) B: reference-bearing register (4 bits) C: type index (16 bits)	Store in the given destination register 1 if the indicated reference is an instance of the given type, or 0 if not. Note: Since B must always be a reference (and not a primitive value), this will always result in 0 being stored if C refers to a primitive type.
	[0x21] = Instr12x:subclass{name='array-length'},			-- 21 12x	array-length vA, vB	A: destination register (4 bits) B: array reference-bearing register (4 bits)	Store in the given destination register the length of the indicated array, in entries
	[0x22] = Instr21c_type:subclass{name='new-instance'},			-- 22 21c	new-instance vAA, type@BBBB	A: destination register (8 bits) B: type index	Construct a new instance of the indicated type, storing a reference to it in the destination. The type must refer to a non-array class.
	[0x23] = Instr22c_type:subclass{name='new-array'},			-- 23 22c	new-array vA, vB, type@CCCC	A: destination register (4 bits) B: size register C: type index	Construct a new array of the indicated type and size. The type must be an array type.
	[0x24] = Instr35c_type:subclass{name='filled-new-array'},			-- 24 35c	filled-new-array {vC, vD, vE, vF, vG}, type@BBBB	A: array size and argument word count (4 bits) B: type index (16 bits) C..G: argument registers (4 bits each)	Construct an array of the given type and size, filling it with the supplied contents. The type must be an array type. The array's contents must be single-word (that is, no arrays of long or double, but reference types are acceptable). The constructed instance is stored as a "result" in the same way that the method invocation instructions store their results, so the constructed instance must be moved to a register with an immediately subsequent move-result-object instruction (if it is to be used).
	[0x25] = Instr3rc_type:subclass{name='filled-new-array/range'},			-- 25 3rc	filled-new-array/range {vCCCC .. vNNNN}, type@BBBB	A: array size and argument word count (8 bits) B: type index (16 bits) C: first argument register (16 bits) N = A + C - 1	Construct an array of the given type and size, filling it with the supplied contents. Clarifications and restrictions are the same as filled-new-array, described above.
	[0x26] = Instr31t:subclass{name='fill-array-data'},			-- 26 31t	fill-array-data vAA, +BBBBBBBB (with supplemental data as specified below in "fill-array-data-payload Format")	A: array reference (8 bits) B: signed "branch" offset to table data pseudo-instruction (32 bits)	Fill the given array with the indicated data. The reference must be to an array of primitives, and the data table must match it in type and must contain no more elements than will fit in the array. That is, the array may be larger than the table, and if so, only the initial elements of the array are set, leaving the remainder alone.
	[0x27] = Instr11x:subclass{name='throw'},			-- 27 11x	throw vAA	A: exception-bearing register (8 bits) Throw the indicated exception.
	[0x28] = Instr10t:subclass{name='goto'},			-- 28 10t	goto +AA	A: signed branch offset (8 bits)	Unconditionally jump to the indicated instruction. Note: The branch offset must not be 0. (A spin loop may be legally constructed either with goto/32 or by including a nop as a target before the branch.)
	[0x29] = Instr20t:subclass{name='goto/16'},			-- 29 20t	goto/16 +AAAA	A: signed branch offset (16 bits) Unconditionally jump to the indicated instruction. Note: The branch offset must not be 0. (A spin loop may be legally constructed either with goto/32 or by including a nop as a target before the branch.)
	[0x2a] = Instr30t:subclass{name='goto/32'},			-- 2a 30t	goto/32 +AAAAAAAA	A: signed branch offset (32 bits) Unconditionally jump to the indicated instruction.
	[0x2b] = Instr31t:subclass{name='packed-switch'},			-- 2b 31t	packed-switch vAA, +BBBBBBBB (with supplemental data as specified below in "packed-switch-payload Format")	A: register to test B: signed "branch" offset to table data pseudo-instruction (32 bits)	Jump to a new instruction based on the value in the given register, using a table of offsets corresponding to each value in a particular integral range, or fall through to the next instruction if there is no match.
	[0x2c] = Instr31t:subclass{name='sparse-switch'},			-- 2c 31t	sparse-switch vAA, +BBBBBBBB (with supplemental data as specified below in "sparse-switch-payload Format")	A: register to test B: signed "branch" offset to table data pseudo-instruction (32 bits)	Jump to a new instruction based on the value in the given register, using an ordered table of value-offset pairs, or fall through to the next instruction if there is no match.
	[0x2d] = Instr23x:subclass{name='cmpl-float'},			-- 2d 23x	cmpl-float vAA, vBB, vCC
	[0x2e] = Instr23x:subclass{name='cmpg-float'},			-- 2e 23x	cmpg-float vAA, vBB, vCC
	[0x2f] = Instr23x:subclass{name='cmpl-double'},			-- 2f 23x	cmpl-double vAA, vBB, vCC
	[0x30] = Instr23x:subclass{name='cmpg-double'},			-- 30 23x	cmpg-double vAA, vBB, vCC
	[0x31] = Instr23x:subclass{name='cmp-long'},			-- 31 23x	cmp-long vAA, vBB, vCC		A: destination register (8 bits) B: first source register or pair C: second source register or pair	Perform the indicated floating point or long comparison, setting a to 0 if b == c, 1 if b > c, or -1 if b < c. The "bias" listed for the floating point operations indicates how NaN comparisons are treated: "gt bias" instructions return 1 for NaN comparisons, and "lt bias" instructions return -1. For example, to check to see if floating point x < y it is advisable to use cmpg-float; a result of -1 indicates that the test was true, and the other values indicate it was false either due to a valid comparison or because one of the values was NaN.
	[0x32] = Instr22t:subclass{name='if-eq'},			-- 32 22t	if-eq vA, vB, +CCCC
	[0x33] = Instr22t:subclass{name='if-ne'},			-- 33 22t	if-ne vA, vB, +CCCC
	[0x34] = Instr22t:subclass{name='if-lt'},			-- 34 22t	if-lt vA, vB, +CCCC
	[0x35] = Instr22t:subclass{name='if-ge'},			-- 35 22t	if-ge vA, vB, +CCCC
	[0x36] = Instr22t:subclass{name='if-gt'},			-- 36 22t	if-gt vA, vB, +CCCC
	[0x37] = Instr22t:subclass{name='if-le'},			-- 37 22t	if-le vA, vB, +CCCC A: first register to test (4 bits) B: second register to test (4 bits) C: signed branch offset (16 bits)	Branch to the given destination if the given two registers' values compare as specified. Note: The branch offset must not be 0. (A spin loop may be legally constructed either by branching around a backward goto or by including a nop as a target before the branch.)
	[0x38] = Instr21t:subclass{name='if-eqz'},			-- 38 21t	if-eqz vAA, +BBBB
	[0x39] = Instr21t:subclass{name='if-nez'},			-- 39 21t	if-nez vAA, +BBBB
	[0x3a] = Instr21t:subclass{name='if-ltz'},			-- 3a 21t	if-ltz vAA, +BBBB
	[0x3b] = Instr21t:subclass{name='if-gez'},			-- 3b 21t	if-gez vAA, +BBBB
	[0x3c] = Instr21t:subclass{name='if-gtz'},			-- 3c 21t	if-gtz vAA, +BBBB
	[0x3d] = Instr21t:subclass{name='if-lez'},			-- 3d 21t	if-lez vAA, +BBBB A: register to test (8 bits) B: signed branch offset (16 bits)	Branch to the given destination if the given register's value compares with 0 as specified. Note: The branch offset must not be 0. (A spin loop may be legally constructed either by branching around a backward goto or by including a nop as a target before the branch.)
	[0x3e] = Instr10x:subclass{name='unused'},			-- 3e 10x	unused	 	unused
	[0x3f] = Instr10x:subclass{name='unused'},			-- 3f 10x	unused	 	unused
	[0x40] = Instr10x:subclass{name='unused'},			-- 40 10x	unused	 	unused
	[0x41] = Instr10x:subclass{name='unused'},			-- 41 10x	unused	 	unused
	[0x42] = Instr10x:subclass{name='unused'},			-- 42 10x	unused	 	unused
	[0x43] = Instr10x:subclass{name='unused'},			-- 43 10x	unused	 	unused
	[0x44] = Instr23x:subclass{name='aget'},			-- 44 23x	aget vAA, vBB, vCC
	[0x45] = Instr23x:subclass{name='aget-wide'},			-- 45 23x	aget-wide vAA, vBB, vCC
	[0x46] = Instr23x:subclass{name='aget-object'},			-- 46 23x	aget-object vAA, vBB, vCC
	[0x47] = Instr23x:subclass{name='aget-boolean'},			-- 47 23x	aget-boolean vAA, vBB, vCC
	[0x48] = Instr23x:subclass{name='aget-byte'},			-- 48 23x	aget-byte vAA, vBB, vCC
	[0x49] = Instr23x:subclass{name='aget-char'},			-- 49 23x	aget-char vAA, vBB, vCC
	[0x4a] = Instr23x:subclass{name='aget-short'},			-- 4a 23x	aget-short vAA, vBB, vCC
	[0x4b] = Instr23x:subclass{name='aput'},			-- 4b 23x	aput vAA, vBB, vCC
	[0x4c] = Instr23x:subclass{name='aput-wide'},			-- 4c 23x	aput-wide vAA, vBB, vCC
	[0x4d] = Instr23x:subclass{name='aput-object'},			-- 4d 23x	aput-object vAA, vBB, vCC
	[0x4e] = Instr23x:subclass{name='aput-boolean'},			-- 4e 23x	aput-boolean vAA, vBB, vCC
	[0x4f] = Instr23x:subclass{name='aput-byte'},			-- 4f 23x	aput-byte vAA, vBB, vCC
	[0x50] = Instr23x:subclass{name='aput-char'},			-- 50 23x	aput-char vAA, vBB, vCC
	[0x51] = Instr23x:subclass{name='aput-short'},			-- 51 23x	aput-short vAA, vBB, vCC	A: value register or pair; may be source or dest (8 bits) B: array register (8 bits) C: index register (8 bits)	Perform the identified array operation at the identified index of the given array, loading or storing into the value register.
	[0x52] = Instr22c_field:subclass{name='iget'},			-- 52 22c	iget vA, vB, field@CCCC
	[0x53] = Instr22c_field:subclass{name='iget-wide'},			-- 53 22c	iget-wide vA, vB, field@CCCC
	[0x54] = Instr22c_field:subclass{name='iget-object'},			-- 54 22c	iget-object vA, vB, field@CCCC
	[0x55] = Instr22c_field:subclass{name='iget-boolean'},			-- 55 22c	iget-boolean vA, vB, field@CCCC
	[0x56] = Instr22c_field:subclass{name='iget-byte'},			-- 56 22c	iget-byte vA, vB, field@CCCC
	[0x57] = Instr22c_field:subclass{name='iget-char'},			-- 57 22c	iget-char vA, vB, field@CCCC
	[0x58] = Instr22c_field:subclass{name='iget-short'},			-- 58 22c	iget-short vA, vB, field@CCCC
	[0x59] = Instr22c_field:subclass{name='iput'},			-- 59 22c	iput vA, vB, field@CCCC
	[0x5a] = Instr22c_field:subclass{name='iput-wide'},			-- 5a 22c	iput-wide vA, vB, field@CCCC
	[0x5b] = Instr22c_field:subclass{name='iput-object'},			-- 5b 22c	iput-object vA, vB, field@CCCC
	[0x5c] = Instr22c_field:subclass{name='iput-boolean'},			-- 5c 22c	iput-boolean vA, vB, field@CCCC
	[0x5d] = Instr22c_field:subclass{name='iput-byte'},			-- 5d 22c	iput-byte vA, vB, field@CCCC
	[0x5e] = Instr22c_field:subclass{name='iput-char'},			-- 5e 22c	iput-char vA, vB, field@CCCC
	[0x5f] = Instr22c_field:subclass{name='iput-short'},			-- 5f 22c	iput-short vA, vB, field@CCCC	A: value register or pair; may be source or dest (4 bits) B: object register (4 bits) C: instance field reference index (16 bits)	Perform the identified object instance field operation with the identified field, loading or storing into the value register. Note: These opcodes are reasonable candidates for static linking, altering the field argument to be a more direct offset.
	[0x60] = Instr21c_field:subclass{name='sget'},			-- 60 21c	sget vAA, field@BBBB
	[0x61] = Instr21c_field:subclass{name='sget-wide'},			-- 61 21c	sget-wide vAA, field@BBBB
	[0x62] = Instr21c_field:subclass{name='sget-object'},			-- 62 21c	sget-object vAA, field@BBBB
	[0x63] = Instr21c_field:subclass{name='sget-boolean'},			-- 63 21c	sget-boolean vAA, field@BBBB
	[0x64] = Instr21c_field:subclass{name='sget-byte'},			-- 64 21c	sget-byte vAA, field@BBBB
	[0x65] = Instr21c_field:subclass{name='sget-char'},			-- 65 21c	sget-char vAA, field@BBBB
	[0x66] = Instr21c_field:subclass{name='sget-short'},			-- 66 21c	sget-short vAA, field@BBBB
	[0x67] = Instr21c_field:subclass{name='sput'},			-- 67 21c	sput vAA, field@BBBB
	[0x68] = Instr21c_field:subclass{name='sput-wide'},			-- 68 21c	sput-wide vAA, field@BBBB
	[0x69] = Instr21c_field:subclass{name='sput-object'},			-- 69 21c	sput-object vAA, field@BBBB
	[0x6a] = Instr21c_field:subclass{name='sput-boolean'},			-- 6a 21c	sput-boolean vAA, field@BBBB
	[0x6b] = Instr21c_field:subclass{name='sput-byte'},			-- 6b 21c	sput-byte vAA, field@BBBB
	[0x6c] = Instr21c_field:subclass{name='sput-char'},			-- 6c 21c	sput-char vAA, field@BBBB
	[0x6d] = Instr21c_field:subclass{name='sput-short'},			-- 6d 21c	sput-short vAA, field@BBBB	A: value register or pair; may be source or dest (8 bits) B: static field reference index (16 bits)	Perform the identified object static field operation with the identified static field, loading or storing into the value register. Note: These opcodes are reasonable candidates for static linking, altering the field argument to be a more direct offset.
	[0x6e] = Instr35c_method:subclass{name='invoke-virtual'},			-- 6e 35c	invoke-virtual {vC, vD, vE, vF, vG}, meth@BBBB
	[0x6f] = Instr35c_method:subclass{name='invoke-super'},			-- 6f 35c	invoke-super {vC, vD, vE, vF, vG}, meth@BBBB
	[0x70] = Instr35c_method:subclass{name='invoke-direct'},			-- 70 35c	invoke-direct {vC, vD, vE, vF, vG}, meth@BBBB
	[0x71] = Instr35c_method:subclass{name='invoke-static'},			-- 71 35c	invoke-static {vC, vD, vE, vF, vG}, meth@BBBB
	[0x72] = Instr35c_method:subclass{name='invoke-interface'},			-- 72 35c	invoke-interface {vC, vD, vE, vF, vG}, meth@BBBB	A: argument word count (4 bits) B: method reference index (16 bits) C..G: argument registers (4 bits each)	Call the indicated method. The result (if any) may be stored with an appropriate move-result* variant as the immediately subsequent instruction. invoke-virtual is used to invoke a normal virtual method which is a method that isn't static, private or a constructor. When the method_id references a method of a non-interface class, invoke-super is used to invoke the closest superclass's virtual method (as opposed to the one with the same method_id in the calling class). The same method restrictions hold as for invoke-virtual. In Dex files version 037 or later, if the method_id refers to an interface method, invoke-super is used to invoke the most specific, non-overridden version of that method defined on that interface. The same method restrictions hold as for invoke-virtual. In Dex files prior to version 037, having an interface method_id is illegal and undefined. invoke-direct is used to invoke a non-static direct method (that is, an instance method that is by its nature non-overridable, namely either a private instance method or a constructor). invoke-static is used to invoke a static method (which is always considered a direct method). invoke-interface is used to invoke an interface method, that is, on an object whose concrete class isn't known, using a method_id that refers to an interface. Note: These opcodes are reasonable candidates for static linking, altering the method argument to be a more direct offset (or pair thereof).
	[0x73] = Instr10x:subclass{name='unused'},			-- 73 10x	unused		unused
	[0x74] = Instr3rc_method:subclass{name='invoke-virtual/range'},			-- 74 3rc	invoke-virtual/range {vCCCC .. vNNNN}, meth@BBBB
	[0x75] = Instr3rc_method:subclass{name='invoke-super/range'},			-- 75 3rc	invoke-super/range {vCCCC .. vNNNN}, meth@BBBB
	[0x76] = Instr3rc_method:subclass{name='invoke-direct/range'},			-- 76 3rc	invoke-direct/range {vCCCC .. vNNNN}, meth@BBBB
	[0x77] = Instr3rc_method:subclass{name='invoke-static/range'},			-- 77 3rc	invoke-static/range {vCCCC .. vNNNN}, meth@BBBB
	[0x78] = Instr3rc_method:subclass{name='invoke-interface/range'},			-- 78 3rc	invoke-interface/range {vCCCC .. vNNNN}, meth@BBBB	A: argument word count (8 bits) B: method reference index (16 bits) C: first argument register (16 bits) N = A + C - 1	Call the indicated method. See first invoke-kind description above for details, caveats, and suggestions.
	[0x79] = Instr10x:subclass{name='unused'},			-- 79 10x	unused		unused
	[0x7a] = Instr10x:subclass{name='unused'},			-- 7a 10x	unused		unused
	[0x7b] = Instr12x:subclass{name='neg-int'},			-- 7b 12x	neg-int vA, vB
	[0x7c] = Instr12x:subclass{name='not-int'},			-- 7c 12x	not-int vA, vB
	[0x7d] = Instr12x:subclass{name='neg-long'},			-- 7d 12x	neg-long vA, vB
	[0x7e] = Instr12x:subclass{name='not-long'},			-- 7e 12x	not-long vA, vB
	[0x7f] = Instr12x:subclass{name='neg-float'},			-- 7f 12x	neg-float vA, vB
	[0x80] = Instr12x:subclass{name='neg-double'},			-- 80 12x	neg-double vA, vB
	[0x81] = Instr12x:subclass{name='int-to-long'},			-- 81 12x	int-to-long vA, vB
	[0x82] = Instr12x:subclass{name='int-to-float'},			-- 82 12x	int-to-float vA, vB
	[0x83] = Instr12x:subclass{name='int-to-double'},			-- 83 12x	int-to-double vA, vB
	[0x84] = Instr12x:subclass{name='long-to-int'},			-- 84 12x	long-to-int vA, vB
	[0x85] = Instr12x:subclass{name='long-to-float'},			-- 85 12x	long-to-float vA, vB
	[0x86] = Instr12x:subclass{name='long-to-double'},			-- 86 12x	long-to-double vA, vB
	[0x87] = Instr12x:subclass{name='float-to-int'},			-- 87 12x	float-to-int vA, vB
	[0x88] = Instr12x:subclass{name='float-to-long'},			-- 88 12x	float-to-long vA, vB
	[0x89] = Instr12x:subclass{name='float-to-double'},			-- 89 12x	float-to-double vA, vB
	[0x8a] = Instr12x:subclass{name='double-to-int'},			-- 8a 12x	double-to-int vA, vB
	[0x8b] = Instr12x:subclass{name='double-to-long'},			-- 8b 12x	double-to-long vA, vB
	[0x8c] = Instr12x:subclass{name='double-to-float'},			-- 8c 12x	double-to-float vA, vB
	[0x8d] = Instr12x:subclass{name='int-to-byte'},			-- 8d 12x	int-to-byte vA, vB
	[0x8e] = Instr12x:subclass{name='int-to-char'},			-- 8e 12x	int-to-char vA, vB
	[0x8f] = Instr12x:subclass{name='int-to-short'},			-- 8f 12x	int-to-short vA, vB	A: destination register or pair (4 bits) B: source register or pair (4 bits)	Perform the identified unary operation on the source register, storing the result in the destination register.
	[0x90] = Instr23x:subclass{name='add-int'},			-- 90 23x	add-int vAA, vBB, vCC
	[0x91] = Instr23x:subclass{name='sub-int'},			-- 91 23x	sub-int vAA, vBB, vCC
	[0x92] = Instr23x:subclass{name='mul-int'},			-- 92 23x	mul-int vAA, vBB, vCC
	[0x93] = Instr23x:subclass{name='div-int'},			-- 93 23x	div-int vAA, vBB, vCC
	[0x94] = Instr23x:subclass{name='rem-int'},			-- 94 23x	rem-int vAA, vBB, vCC
	[0x95] = Instr23x:subclass{name='and-int'},			-- 95 23x	and-int vAA, vBB, vCC
	[0x96] = Instr23x:subclass{name='or-int'},			-- 96 23x	or-int vAA, vBB, vCC
	[0x97] = Instr23x:subclass{name='xor-int'},			-- 97 23x	xor-int vAA, vBB, vCC
	[0x98] = Instr23x:subclass{name='shl-int'},			-- 98 23x	shl-int vAA, vBB, vCC
	[0x99] = Instr23x:subclass{name='shr-int'},			-- 99 23x	shr-int vAA, vBB, vCC
	[0x9a] = Instr23x:subclass{name='ushr-int'},			-- 9a 23x	ushr-int vAA, vBB, vCC
	[0x9b] = Instr23x:subclass{name='add-long'},			-- 9b 23x	add-long vAA, vBB, vCC
	[0x9c] = Instr23x:subclass{name='sub-long'},			-- 9c 23x	sub-long vAA, vBB, vCC
	[0x9d] = Instr23x:subclass{name='mul-long'},			-- 9d 23x	mul-long vAA, vBB, vCC
	[0x9e] = Instr23x:subclass{name='div-long'},			-- 9e 23x	div-long vAA, vBB, vCC
	[0x9f] = Instr23x:subclass{name='rem-long'},			-- 9f 23x	rem-long vAA, vBB, vCC
	[0xa0] = Instr23x:subclass{name='and-long'},			-- a0 23x	and-long vAA, vBB, vCC
	[0xa1] = Instr23x:subclass{name='or-long'},			-- a1 23x	or-long vAA, vBB, vCC
	[0xa2] = Instr23x:subclass{name='xor-long'},			-- a2 23x	xor-long vAA, vBB, vCC
	[0xa3] = Instr23x:subclass{name='shl-long'},			-- a3 23x	shl-long vAA, vBB, vCC
	[0xa4] = Instr23x:subclass{name='shr-long'},			-- a4 23x	shr-long vAA, vBB, vCC
	[0xa5] = Instr23x:subclass{name='ushr-long'},			-- a5 23x	ushr-long vAA, vBB, vCC
	[0xa6] = Instr23x:subclass{name='add-float'},			-- a6 23x	add-float vAA, vBB, vCC
	[0xa7] = Instr23x:subclass{name='sub-float'},			-- a7 23x	sub-float vAA, vBB, vCC
	[0xa8] = Instr23x:subclass{name='mul-float'},			-- a8 23x	mul-float vAA, vBB, vCC
	[0xa9] = Instr23x:subclass{name='div-float'},			-- a9 23x	div-float vAA, vBB, vCC
	[0xaa] = Instr23x:subclass{name='rem-float'},			-- aa 23x	rem-float vAA, vBB, vCC
	[0xab] = Instr23x:subclass{name='add-double'},			-- ab 23x	add-double vAA, vBB, vCC
	[0xac] = Instr23x:subclass{name='sub-double'},			-- ac 23x	sub-double vAA, vBB, vCC
	[0xad] = Instr23x:subclass{name='mul-double'},			-- ad 23x	mul-double vAA, vBB, vCC
	[0xae] = Instr23x:subclass{name='div-double'},			-- ae 23x	div-double vAA, vBB, vCC
	[0xaf] = Instr23x:subclass{name='rem-double'},			-- af 23x	rem-double vAA, vBB, vCC	A: destination register or pair (8 bits) B: first source register or pair (8 bits) C: second source register or pair (8 bits)	Perform the identified binary operation on the two source registers, storing the result in the destination register. Note: Contrary to other -long mathematical operations (which take register pairs for both their first and their second source), shl-long, shr-long, and ushr-long take a register pair for their first source (the value to be shifted), but a single register for their second source (the shifting distance).
	[0xb0] = Instr12x:subclass{name='add-int/2addr'},			-- b0 12x	add-int/2addr vA, vB
	[0xb1] = Instr12x:subclass{name='sub-int/2addr'},			-- b1 12x	sub-int/2addr vA, vB
	[0xb2] = Instr12x:subclass{name='mul-int/2addr'},			-- b2 12x	mul-int/2addr vA, vB
	[0xb3] = Instr12x:subclass{name='div-int/2addr'},			-- b3 12x	div-int/2addr vA, vB
	[0xb4] = Instr12x:subclass{name='rem-int/2addr'},			-- b4 12x	rem-int/2addr vA, vB
	[0xb5] = Instr12x:subclass{name='and-int/2addr'},			-- b5 12x	and-int/2addr vA, vB
	[0xb6] = Instr12x:subclass{name='or-int/2addr'},			-- b6 12x	or-int/2addr vA, vB
	[0xb7] = Instr12x:subclass{name='xor-int/2addr'},			-- b7 12x	xor-int/2addr vA, vB
	[0xb8] = Instr12x:subclass{name='shl-int/2addr'},			-- b8 12x	shl-int/2addr vA, vB
	[0xb9] = Instr12x:subclass{name='shr-int/2addr'},			-- b9 12x	shr-int/2addr vA, vB
	[0xba] = Instr12x:subclass{name='ushr-int/2addr'},			-- ba 12x	ushr-int/2addr vA, vB
	[0xbb] = Instr12x:subclass{name='add-long/2addr'},			-- bb 12x	add-long/2addr vA, vB
	[0xbc] = Instr12x:subclass{name='sub-long/2addr'},			-- bc 12x	sub-long/2addr vA, vB
	[0xbd] = Instr12x:subclass{name='mul-long/2addr'},			-- bd 12x	mul-long/2addr vA, vB
	[0xbe] = Instr12x:subclass{name='div-long/2addr'},			-- be 12x	div-long/2addr vA, vB
	[0xbf] = Instr12x:subclass{name='rem-long/2addr'},			-- bf 12x	rem-long/2addr vA, vB
	[0xc0] = Instr12x:subclass{name='and-long/2addr'},			-- c0 12x	and-long/2addr vA, vB
	[0xc1] = Instr12x:subclass{name='or-long/2addr'},			-- c1 12x	or-long/2addr vA, vB
	[0xc2] = Instr12x:subclass{name='xor-long/2addr'},			-- c2 12x	xor-long/2addr vA, vB
	[0xc3] = Instr12x:subclass{name='shl-long/2addr'},			-- c3 12x	shl-long/2addr vA, vB
	[0xc4] = Instr12x:subclass{name='shr-long/2addr'},			-- c4 12x	shr-long/2addr vA, vB
	[0xc5] = Instr12x:subclass{name='ushr-long/2addr'},			-- c5 12x	ushr-long/2addr vA, vB
	[0xc6] = Instr12x:subclass{name='add-float/2addr'},			-- c6 12x	add-float/2addr vA, vB
	[0xc7] = Instr12x:subclass{name='sub-float/2addr'},			-- c7 12x	sub-float/2addr vA, vB
	[0xc8] = Instr12x:subclass{name='mul-float/2addr'},			-- c8 12x	mul-float/2addr vA, vB
	[0xc9] = Instr12x:subclass{name='div-float/2addr'},			-- c9 12x	div-float/2addr vA, vB
	[0xca] = Instr12x:subclass{name='rem-float/2addr'},			-- ca 12x	rem-float/2addr vA, vB
	[0xcb] = Instr12x:subclass{name='add-double/2addr'},			-- cb 12x	add-double/2addr vA, vB
	[0xcc] = Instr12x:subclass{name='sub-double/2addr'},			-- cc 12x	sub-double/2addr vA, vB
	[0xcd] = Instr12x:subclass{name='mul-double/2addr'},			-- cd 12x	mul-double/2addr vA, vB
	[0xce] = Instr12x:subclass{name='div-double/2addr'},			-- ce 12x	div-double/2addr vA, vB
	[0xcf] = Instr12x:subclass{name='rem-double/2addr'},			-- cf 12x	rem-double/2addr vA, vB	A: destination and first source register or pair (4 bits) B: second source register or pair (4 bits)	Perform the identified binary operation on the two source registers, storing the result in the first source register. Note: Contrary to other -long/2addr mathematical operations (which take register pairs for both their destination/first source and their second source), shl-long/2addr, shr-long/2addr, and ushr-long/2addr take a register pair for their destination/first source (the value to be shifted), but a single register for their second source (the shifting distance).
	[0xd0] = Instr22s:subclass{name='add-int/lit16'},			-- d0 22s	add-int/lit16 vA, vB, #+CCCC
	[0xd1] = Instr22s:subclass{name='rsub-int'},			-- d1 22s	rsub-int vA, vB, #+CCCC (reverse subtract)
	[0xd2] = Instr22s:subclass{name='mul-int/lit16'},			-- d2 22s	mul-int/lit16 vA, vB, #+CCCC
	[0xd3] = Instr22s:subclass{name='div-int/lit16'},			-- d3 22s	div-int/lit16 vA, vB, #+CCCC
	[0xd4] = Instr22s:subclass{name='rem-int/lit16'},			-- d4 22s	rem-int/lit16 vA, vB, #+CCCC
	[0xd5] = Instr22s:subclass{name='and-int/lit16'},			-- d5 22s	and-int/lit16 vA, vB, #+CCCC
	[0xd6] = Instr22s:subclass{name='or-int/lit16'},			-- d6 22s	or-int/lit16 vA, vB, #+CCCC
	[0xd7] = Instr22s:subclass{name='xor-int/lit16'},			-- d7 22s	xor-int/lit16 vA, vB, #+CCCC	A: destination register (4 bits) B: source register (4 bits) C: signed int constant (16 bits)	Perform the indicated binary op on the indicated register (first argument) and literal value (second argument), storing the result in the destination register. Note: rsub-int does not have a suffix since this version is the main opcode of its family. Also, see below for details on its semantics.
	[0xd8] = Instr22b:subclass{name='add-int/lit8'},			-- d8 22b	add-int/lit8 vAA, vBB, #+CC
	[0xd9] = Instr22b:subclass{name='rsub-int/lit8'},			-- d9 22b	rsub-int/lit8 vAA, vBB, #+CC
	[0xda] = Instr22b:subclass{name='mul-int/lit8'},			-- da 22b	mul-int/lit8 vAA, vBB, #+CC
	[0xdb] = Instr22b:subclass{name='div-int/lit8'},			-- db 22b	div-int/lit8 vAA, vBB, #+CC
	[0xdc] = Instr22b:subclass{name='rem-int/lit8'},			-- dc 22b	rem-int/lit8 vAA, vBB, #+CC
	[0xdd] = Instr22b:subclass{name='and-int/lit8'},			-- dd 22b	and-int/lit8 vAA, vBB, #+CC
	[0xde] = Instr22b:subclass{name='or-int/lit8'},			-- de 22b	or-int/lit8 vAA, vBB, #+CC
	[0xdf] = Instr22b:subclass{name='xor-int/lit8'},			-- df 22b	xor-int/lit8 vAA, vBB, #+CC
	[0xe0] = Instr22b:subclass{name='shl-int/lit8'},			-- e0 22b	shl-int/lit8 vAA, vBB, #+CC
	[0xe1] = Instr22b:subclass{name='shr-int/lit8'},			-- e1 22b	shr-int/lit8 vAA, vBB, #+CC
	[0xe2] = Instr22b:subclass{name='ushr-int/lit8'},			-- e2 22b	ushr-int/lit8 vAA, vBB, #+CC	A: destination register (8 bits) B: source register (8 bits) C: signed int constant (8 bits)	Perform the indicated binary op on the indicated register (first argument) and literal value (second argument), storing the result in the destination register. Note: See below for details on the semantics of rsub-int.
	[0xe3] = Instr10x:subclass{name='unused'},			-- e3 10x	unused	 	unused
	[0xe4] = Instr10x:subclass{name='unused'},			-- e4 10x	unused	 	unused
	[0xe5] = Instr10x:subclass{name='unused'},			-- e5 10x	unused	 	unused
	[0xe6] = Instr10x:subclass{name='unused'},			-- e6 10x	unused	 	unused
	[0xe7] = Instr10x:subclass{name='unused'},			-- e7 10x	unused	 	unused
	[0xe8] = Instr10x:subclass{name='unused'},			-- e8 10x	unused	 	unused
	[0xe9] = Instr10x:subclass{name='unused'},			-- e9 10x	unused	 	unused
	[0xea] = Instr10x:subclass{name='unused'},			-- ea 10x	unused	 	unused
	[0xeb] = Instr10x:subclass{name='unused'},			-- eb 10x	unused	 	unused
	[0xec] = Instr10x:subclass{name='unused'},			-- ec 10x	unused	 	unused
	[0xed] = Instr10x:subclass{name='unused'},			-- ed 10x	unused	 	unused
	[0xee] = Instr10x:subclass{name='unused'},			-- ee 10x	unused	 	unused
	[0xef] = Instr10x:subclass{name='unused'},			-- ef 10x	unused	 	unused
	[0xf0] = Instr10x:subclass{name='unused'},			-- f0 10x	unused	 	unused
	[0xf1] = Instr10x:subclass{name='unused'},			-- f1 10x	unused	 	unused
	[0xf2] = Instr10x:subclass{name='unused'},			-- f2 10x	unused	 	unused
	[0xf3] = Instr10x:subclass{name='unused'},			-- f3 10x	unused	 	unused
	[0xf4] = Instr10x:subclass{name='unused'},			-- f4 10x	unused	 	unused
	[0xf5] = Instr10x:subclass{name='unused'},			-- f5 10x	unused	 	unused
	[0xf6] = Instr10x:subclass{name='unused'},			-- f6 10x	unused	 	unused
	[0xf7] = Instr10x:subclass{name='unused'},			-- f7 10x	unused	 	unused
	[0xf8] = Instr10x:subclass{name='unused'},			-- f8 10x	unused	 	unused
	[0xf9] = Instr10x:subclass{name='unused'},			-- f9 10x	unused	 	unused
	[0xfa] = Instr45cc:subclass{name='invoke-polymorphic'},			-- fa 45cc	invoke-polymorphic {vC, vD, vE, vF, vG}, meth@BBBB, proto@HHHH	A: argument word count (4 bits) B: method reference index (16 bits) C: receiver (4 bits) D..G: argument registers (4 bits each) H: prototype reference index (16 bits)	Invoke the indicated signature polymorphic method. The result (if any) may be stored with an appropriate move-result* variant as the immediately subsequent instruction. The method reference must be to a signature polymorphic method, such as java.lang.invoke.MethodHandle.invoke or java.lang.invoke.MethodHandle.invokeExact. The receiver must be an object supporting the signature polymorphic method being invoked. The prototype reference describes the argument types provided and the expected return type. The invoke-polymorphic bytecode may raise exceptions when it executes. The exceptions are described in the API documentation for the signature polymorphic method being invoked. Present in Dex files from version 038 onwards.
	[0xfb] = Instr4rcc:subclass{name='invoke-polymorphic/range'},			-- fb 4rcc	invoke-polymorphic/range {vCCCC .. vNNNN}, meth@BBBB, proto@HHHH	A: argument word count (8 bits) B: method reference index (16 bits) C: receiver (16 bits) H: prototype reference index (16 bits) N = A + C - 1	Invoke the indicated method handle. See the invoke-polymorphic description above for details. Present in Dex files from version 038 onwards.
	[0xfc] = Instr35c_callsite:subclass{name='invoke-custom'},			-- fc 35c	invoke-custom {vC, vD, vE, vF, vG}, call_site@BBBB	A: argument word count (4 bits) B: call site reference index (16 bits) C..G: argument registers (4 bits each)	Resolves and invokes the indicated call site. The result from the invocation (if any) may be stored with an appropriate move-result* variant as the immediately subsequent instruction. This instruction executes in two phases: call site resolution and call site invocation. Call site resolution checks whether the indicated call site has an associated java.lang.invoke.CallSite instance. If not, the bootstrap linker method for the indicated call site is invoked using arguments present in the DEX file (see call_site_item). The bootstrap linker method returns a java.lang.invoke.CallSite instance that will then be associated with the indicated call site if no association exists. Another thread may have already made the association first, and if so execution of the instruction continues with the first associated java.lang.invoke.CallSite instance. Call site invocation is made on the java.lang.invoke.MethodHandle target of the resolved java.lang.invoke.CallSite instance. The target is invoked as if executing invoke-polymorphic (described above) using the method handle and arguments to the invoke-custom instruction as the arguments to an exact method handle invocation. Exceptions raised by the bootstrap linker method are wrapped in a java.lang.BootstrapMethodError. A BootstrapMethodError is also raised if: the bootstrap linker method fails to return a java.lang.invoke.CallSite instance. the returned java.lang.invoke.CallSite has a null method handle target. the method handle target is not of the requested type. Present in Dex files from version 038 onwards.
	[0xfd] = Instr3rc_callsite:subclass{name='invoke-custom/range'},			-- fd 3rc	invoke-custom/range {vCCCC .. vNNNN}, call_site@BBBB	A: argument word count (8 bits) B: call site reference index (16 bits) C: first argument register (16-bits) N = A + C - 1	Resolve and invoke a call site. See the invoke-custom description above for details. Present in Dex files from version 038 onwards.
	[0xfe] = Instr21c_method:subclass{name='const-method-handle'},			-- fe 21c	const-method-handle vAA, method_handle@BBBB	A: destination register (8 bits) B: method handle index (16 bits)	Move a reference to the method handle specified by the given index into the specified register. Present in Dex files from version 039 onwards.
	[0xff] = Instr21c_proto:subclass{name='const-method-type'},			-- ff 21c	const-method-type vAA, proto@BBBB	A: destination register (8 bits) B: method prototype reference (16 bits)	Move a reference to the method prototype specified by the given index into the specified register. Present in Dex files from version 039 onwards.
}
local opForInstName = table.map(instDescForOp, function(inst,op)
	return op, inst.name
end)

local JavaASMDex = class()
JavaASMDex.__name = 'JavaASMDex'

--[[
similar as JavaASMClass
key differences in ASMDex vs ASMClass:
- .dex files can have multiple classes, so
- - they will have a .class table holding the, thisClass, superClass, and class access flags
- - each method and field will have a .class reference
- internally .dex uses some weird convoluted arg type list and "shorty" (smh Google...) arg string that is a typical Java function jni arg signature string but with a) return type first, b) parenthesis removed, and c) all class names removed.
- .dex methods havae "maxRegs", "regsIn", "regsOut" where .class methods have "maxLocals" and "maxStacks"
- the instruction sets are different
- optional attributes differ
--]]
function JavaASMDex:init(args)
	if type(args) == 'string' then
		self:readData(args)	-- assume its raw data
	elseif type(args) == 'nil' then
	elseif type(args) == 'table' then
		for k,v in pairs(args) do
			self[k] = v
		end

		-- while we're here, prepare / validate args:
		for _,method in ipairs(self.methods) do
			-- parse method.code if it is instructions
			if type(method.code) == 'string' then

				-- argument validation:
				-- do this here or upon ctor?
				method.code = string.split(string.trim(method.code), '\n')
					:mapi(function(line)
						return string.trim(line)
					end)
					:filteri(function(line)
						return line:sub(1, #self.lineComment) ~= self.lineComment
					end)
					:mapi(function(line)
						return string.split(line, '%s+')
					end)

			end
		end
	else
		error("idk how to init this")
	end
end


-------------------------------- READING --------------------------------


-- static ctor
function JavaASMDex:fromFile(filename)
	local o = JavaASMDex()
	o:readData((assert(path(filename):read())))
	return o
end


function JavaASMDex:readData(data)
	local blob = ReadBlobLE(data)
	assert.eq(blob:readString(4), 'dex\n')
	local version = blob:readString(4)	-- 3 text chars of numbers with null term ...
--DEBUG:print('version', string.hex(version))
	local checksum = blob:readu4()
--DEBUG:print('checksum = 0x'..bit.tohex(checksum, 8))
	local sha1sig = blob:readString(20)
--DEBUG:print('sha1sig', string.hex(sha1sig))
	local fileSize = blob:readu4()
--DEBUG:print('fileSize', fileSize)
	local headerSize = blob:readu4()
--DEBUG:print('headerSize', headerSize)
	local endianTag = blob:readu4()
--DEBUG:print('endianTag = 0x'..bit.tohex(endianTag, 8))
	if endianTag == 0x78563412 then
		-- then do I flip size and checksum as well?
		blob.littleEndian = false
	elseif endianTag == 0x12345678 then
		-- safe
	else
		error('endian is a bad value: 0x'..bit.tohex(endianTag, 8)..', something else will probably go wrong.\n')
	end
	assert.eq(fileSize, #data, "fileSize didn't match")	-- when does size not equal #data?

	local numLinks = blob:readu4()
	local linkOfs = blob:readu4()
--DEBUG:print('link count', numLinks,'ofs', linkOfs)
	if numLinks ~= 0 then
io.stderr:write('TODO support dynamically-linked .dex files\n')
	end

	local mapOfs = blob:readu4()
--DEBUG:print('map ofs', mapOfs)

	local numStrings = blob:readu4()
	local stringOfsOfs = blob:readu4()
--DEBUG:print('stringId count', numStrings, 'ofs', stringOfsOfs)

	local numTypes = blob:readu4()
	local typeOfs = blob:readu4()
--DEBUG:print('typeId count', numTypes,'ofs', typeOfs)

	local numProtos = blob:readu4()
	local protoOfs = blob:readu4()
--DEBUG:print('protoId count', numProtos,'ofs', protoOfs)

	local numFields = blob:readu4()
	local fieldOfs = blob:readu4()
--DEBUG:print('fieldId count', numFields,'ofs', fieldOfs)

	local numMethods = blob:readu4()
	local methodOfs = blob:readu4()
--DEBUG:print('methodId count', numMethods,'ofs', methodOfs)

	local numClasses = blob:readu4()
	local classOfs = blob:readu4()
--DEBUG:print('classDef count', numClasses,'ofs', classOfs)

	-- wait is this used for anything, or just annotation as to where the 'extra' data of other header fields puts stuff?
	local numDatas = blob:readu4()
	local datasOfs = blob:readu4()
--DEBUG:print('data count', numDatas,'ofs', datasOfs)

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
	-- it's redundant.  and stupid.
	if mapOfs ~= 0 then
		blob.ofs = mapOfs
		local count = blob:readu4()
		for i=0,count-1 do
			local map = {}
			map.type = assert.index(mapListTypes, blob:readu2())
			blob:readu2()	-- unused
			map.count = blob:readu4()
			map.offset = blob:readu4()
--DEBUG:print('map['..i..'] = '..require 'ext.tolua'(map))
		end
	end

	-- string offset points to a list of uint32_t's which point to the string data
	-- ... which start with a uleb128 prefix
	assert.le(0, stringOfsOfs)
	assert.le(stringOfsOfs + ffi.sizeof'uint32_t' * numStrings, fileSize)
	local strings = table()
	self.strings = strings
	for i=0,numStrings-1 do
		blob.ofs = stringOfsOfs + ffi.sizeof'uint32_t' * i
--DEBUG:print('stringOfsOfs', blob.ofs)
		blob.ofs = blob:readu4()
--DEBUG:print('stringOfs', blob.ofs)
		if blob.ofs < 0 or blob.ofs >= fileSize then
			error("string has bad ofs: 0x"..string.hex(blob.ofs))
		end
		local len = blob:readUleb128()
		local str = blob:readString(len)
		strings[i+1] = str
--DEBUG:print('string['..i..'] = '..require 'ext.tolua'(str))
	end

	assert.le(0, typeOfs)
	assert.le(typeOfs + ffi.sizeof'uint32_t' * numTypes, fileSize)
	blob.ofs = typeOfs
	for i=0,numTypes-1 do
		types[i+1] = assert.index(strings, blob:readu4()+1)
--DEBUG:print('type['..i..'] = '..types[i+1])
	end

	assert.le(0, protoOfs)
	assert.le(protoOfs + sizeOfProto * numProtos, fileSize)
	local protos = table()
	self.protos = protos
	for i=0,numProtos-1 do
		blob.ofs = protoOfs + i * sizeOfProto
		local proto = {}
		-- I don't get ShortyDescritpor ... is it redundant to returnType + args?
		local shortyIndex = blob:readu4()
--DEBUG:print('read proto shortyIndex', shortyIndex)		
		local shorty = assert.index(strings, 1 + shortyIndex)
		local returnTypeIndex = blob:readu4()
--DEBUG:print('read proto returnTypeIndex', returnTypeIndex)		
		local returnType = assert.index(types, 1 + returnTypeIndex)

		local argTypeListOfs = blob:readu4()
--DEBUG:print('read proto argTypeListOfs', argTypeListOfs)		
		local argTypes = readTypeList(argTypeListOfs)

		-- sig but in .class format:
		local sig = '('..(argTypes and argTypes:concat() or '')..')'..returnType
		protos[i+1] = sig

--DEBUG:print('proto['..i..'] = '..require 'ext.tolua'(protos[i+1]))
	end

	local sizeOfField = 2*ffi.sizeof'uint32_t'
	assert.le(0, fieldOfs)
	assert.le(fieldOfs + sizeOfField * numFields, fileSize)
	blob.ofs = fieldOfs
	self.fields = table()
	for i=0,numFields-1 do
		local field = {}
		self.fields[i+1] = field
		field.class = assert.index(types, 1 + blob:readu2())
		field.sig = assert.index(types, 1 + blob:readu2())
		field.name = assert.index(strings, 1 + blob:readu4())
	end

	assert.le(0, methodOfs)
	assert.le(methodOfs + 2*ffi.sizeof'uint32_t' * numMethods, fileSize)
	blob.ofs = methodOfs
	self.methods = table()
	for i=0,numMethods-1 do
		local method = {}
		self.methods[i+1] = method
		local classIndex = blob:readu2()
--DEBUG:print('read method class index', classIndex)		
		method.class = assert.index(types, 1 + classIndex)
		local protoIndex = blob:readu2()
--DEBUG:print('read method proto index', protoIndex)		
		method.sig = deepCopy(assert.index(protos, 1 + protoIndex))
		local nameIndex = blob:readu4()
--DEBUG:print('read method name index', nameIndex)	
		method.name = assert.index(strings, 1 + nameIndex)
--DEBUG:print('read method['..i..'] = '..require 'ext.tolua'(method))
	end

	-- so this is interesting
	-- an ASMDex file can be more than one class
	-- oh well, as long as there's one ASMDex per DexLoader or whatever
	assert.le(0, classOfs)
	assert.le(classOfs + sizeOfClass * numClasses, fileSize)
	self.classes = table()
--DEBUG:print('read classDataOfs', classOfs)
	for i=0,numClasses-1 do
		blob.ofs = classOfs + i * sizeOfClass
		local class = {}
		self.classes[i+1] = class
		local thisClassIndex = blob:readu4()
--DEBUG:print('read class thisClassIndex', thisClassIndex)
		class.thisClass = assert.index(types, 1 + thisClassIndex)
		local accessFlags = blob:readu4()
--DEBUG:print('read class accessFlags', accessFlags)
		setFlagsToObj(class, accessFlags, classAccessFlags)
		local superClassIndex = blob:readu4()
--DEBUG:print('read class superClassIndex', superClassIndex)
		class.superClass = assert.index(types, 1 + superClassIndex)
		local interfacesOfs = blob:readu4()
		local sourceFileIndex = blob:readu4()
--DEBUG:print('read class sourceFileIndex', sourceFileIndex)
		class.sourceFile = assert.index(strings, 1 + sourceFileIndex)
		local annotationsOfs = blob:readu4()
		local classDataOfs = blob:readu4()
		local staticValueOfs = blob:readu4()

		-- done reading classdef, read its properties:

		if interfacesOfs ~= 0 then
			class.interfaces = readTypeList(interfacesOfs)
		end

		if annotationsOfs ~= 0 then
			io.stderr:write'TODO annotationsOfs\n'
		end

		if classDataOfs ~= 0 then
			blob.ofs = classDataOfs
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
					assert.lt(codeOfs, fileSize)

					if codeOfs ~= 0 then
						local push = blob.ofs	-- save for later since we're in the middle of decoding classDataOfs
--DEBUG:print('reading code for method', methodIndex)
						blob.ofs = codeOfs

						-- read code
						method.maxRegs = blob:readu2()	-- same as "maxLocals" but for registers?
						method.regsIn = blob:readu2()
						method.regsOut = blob:readu2()
						local numTries = blob:readu2()
						local debugInfoOfs = blob:readu4()
						local numInsns = blob:readu4()	-- "in 16-bit code units..." ... this is the number of uint16_t's
--DEBUG:print('method numInsns ', numInsns)
						local instEndOfs = blob.ofs + bit.lshift(numInsns, 1)
						local code = table()
						method.code = code
						while blob.ofs < instEndOfs do
--DEBUG:io.write(bit.tohex(blob.ofs, 8), ':\t')
							-- Is uint16 instruction order influenced by endian order?
							-- "Also, if this happens to be in an endian-swapped file, then the swapping is only done on individual ushort instances and not on the larger internal structures."
							-- ...whatever that means. "Sometimes." smh.
							-- is the opcode hi and lo swapped as well????
							local lo = blob:readu1()
							local hi = blob:readu1()
							local instDesc = assert.index(instDescForOp, lo)
							local inst = table()
							inst:insert(instDesc.name)
							instDesc.read(inst, hi, blob, self)
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
								try.startAddr = blob:readu4()
								try.numInsts = blob:readu2()
								try.handlerOfs = blob:readu2()
--DEBUG:print('got try #'..j..':', require 'ext.tolua'(try))
								-- "Elements of the array must be non-overlapping in range and in order from low to high address. "
								if lasttry then
									assert.le(lasttry.startAddr + lasttry.numInsts, try.startAddr, "try begins after previous try ends")
								end
								assert.le(try.startAddr + try.numInsts, numInsns, "try extends past file size")
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

						blob.ofs = push
					end
				end
			end
--DEBUG:print('numDirectMethods', numDirectMethods)
--DEBUG:print('numVirtualMethods', numVirtualMethods)
			readMethods(numDirectMethods, true)
			readMethods(numVirtualMethods)
		end

		if staticValueOfs ~= 0 then
			io.stderr:write'TODO staticValueOfs\n'
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

	-- these are now baked into instructions, no longer needed
	self.protos = nil
	self.strings = nil
	self.types = nil

	-- if we are in a one-class file then merge classes[1] with root and remove .class from all fields and methods (cuz its redundant anwaysy)
	if #self.classes == 1 then
		for k,v in pairs(self.classes[1]) do
			self[k] = v
		end
		self.classes = nil
		local classname = self.thisClass
		for _,field in ipairs(self.fields) do
			assert.eq(field.class, classname)
			field.class = nil
		end
		for _,method in ipairs(self.methods) do
			assert.eq(method.class, classname)
			method.class = nil
		end
	end
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

	-- move any class properties from root into a new class object
	-- (but only if there's no .classes already
	self.fields = self.fields or table()
	self.methods = self.methods or table()
	if not self.classes then
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

		for _,field in ipairs(self.fields) do
			field.class = self.thisClass
		end
		for _,method in ipairs(self.methods) do
			method.class = self.thisClass
		end
	end

	self.strings = table()
	self.types = table()
	self.protos = table()
	self.typeLists = table()

	-- table of blobs of converted fields that will either come from .fields which are local to this function, or from field references in instructions
	self.fieldBlobs = table()

	-- return 0-based index into our list of unique values
	local function addUnique(arr, data)
		for i=1,#arr do
			if arr[i] == data then return i-1 end
		end
		arr:insert(data)
		return #arr-1
	end

	-- return 0-based index into strings
	local function addString(str)
		assert.type(str, 'string')
		-- ultimately strings will be preceded by a uleb128 of the length
		-- but equality is the same with the original so dont convert just yet
		local stringIndex = addUnique(self.strings, str)
--DEBUG:print('adding string', stringIndex, str)
		return stringIndex
	end
	self.addString = addString

	-- return 0-based index into types
	local function addType(str)
		assert.type(str, 'string')
		local w = WriteBlobLE()
		local stringIndex = addString(str)
		w:writeu4(stringIndex)
		local b = w:compile()
		local typeIndex = addUnique(self.types, b)
--DEBUG:print('adding type '..typeIndex..' = '..string.hex(b)..' to string '..self.strings[stringIndex+1])
		return typeIndex
	end
	self.addType = addType

	-- returns 0 when the offset should be 0,
	-- otherwise returns a 1-based index into the type lists
	local function addTypeList(typeStrs)
		if not typeStrs then return 0 end
		if #typeStrs == 0 then return 0 end	-- 0 means 0
		local w = WriteBlobLE()
		w:writeu4(#typeStrs)
		for _,typeStr in ipairs(typeStrs) do
			w:writeu2(addType(typeStr))
		end
		-- return 1-based index to-be-replaced later
		local b = w:compile()
		local typeListIndex = addUnique(self.typeLists, b)
--DEBUG:print('adding type list index '..typeListIndex..' '..string.hex(b)..' from '..require 'ext.tolua'(typeStrs))		
		return 1+typeListIndex 
	end

	-- return 0-based index into protos
	local function addProto(sigstr)
--DEBUG:print('addProto', sigstr)
		assert(sigstr)
		-- sig is jni encoded signature string, so "(args args args) return type" no spaces
		local sig = splitMethodJNISig(sigstr)
		assert(sig, "failed to convert sigstr "..require 'ext.tolua'(sigstr))
--DEBUG:print('from', sigstr, 'to', require 'ext.tolua'(sig))

		local shorts = sig:mapi(function(sigi)
			return #sigi > 1 and 'L' or sigi
		end)

		local w = WriteBlobLE()
		local shorty = shorts:concat()
		local shortyIndex = addString(shorty)
--DEBUG:print('adding proto shorty', shorty, 'index', shortyIndex)
		w:writeu4(shortyIndex)

		local returnType = table.remove(sig, 1)
		local returnTypeIndex = addType(returnType)
--DEBUG:print('adding proto returnType', returnType, 'index', returnTypeIndex)		
		w:writeu4(returnTypeIndex)

		local argTypeListIndex = addTypeList(sig)
--DEBUG:print('adding proto argTypeListIndex', argTypeListIndex, require 'ext.tolua'(sig))
		-- notice, the args get stoerd in a a separate list later
		-- so i'll save them in another list
		-- and in place of an offset, i'll just save that list's index for now...
		w:writeu4(argTypeListIndex)

		local b = w:compile()
		local protoIndex = addUnique(self.protos, b)
--DEBUG:print('adding proto', protoIndex, string.hex(b), 'for sig', sigstr)
		return protoIndex
	end
	self.addProto = addProto

	-- be sure to only call this after processing fields
	-- not that it matters?
	local function addField(class, name, sig)
		local w = WriteBlobLE()
		w:writeu2(addType(class))
		w:writeu2(addType(sig))
		w:writeu4(addString(name))
		return addUnique(self.fieldBlobs, w:compile())
	end
	self.addField = addField

	-- extract out unique fields here first to keep fields in-order
	for _,field in ipairs(self.fields) do
		addField(field.class, field.name, field.sig)
		field.accessFlags = getFlagsFromObj(field, fieldAccessFlags)
	end

	self.methodBlobs = table()
	local function addMethod(class, name, sig)
		local w = WriteBlobLE()
		local classIndex = addType(class)
		w:writeu2(classIndex)
--DEBUG:print('adding method with sig', sig)
		local protoIndex = addProto(sig)
		w:writeu2(protoIndex)
		local nameIndex = addString(name)
		w:writeu4(nameIndex)
		local b = w:compile()
		local methodIndex = addUnique(self.methodBlobs, b)
--DEBUG:print('adding method '..methodIndex..' = '..string.hex(b), class, classIndex, sig, protoIndex, name, nameIndex)
		return methodIndex
	end
	self.addMethod = addMethod

-- add methods first so they can be unique first and 1-1 with themselves
--DEBUG:print('checking '..#self.methods..' for writing')
	for i,method in ipairs(self.methods) do
--DEBUG:print('starting method #'..(i-1)..', #methodBlobs', #self.methodBlobs)
--DEBUG:print('checking method '..i..' = '..require'ext.tolua'(method))
		method.methodIndex = addMethod(method.class, method.name, method.sig)
--DEBUG:print('checking method '..(i-1)..' =', method.class, method.name, method.sig, 'index', method.methodIndex)
assert.eq(method.methodIndex+1, i, "did you insert two matching methods?")

		-- the rest goes in the method's extra info
		method.accessFlags = getFlagsFromObj(method, methodAccessFlags)
	end

	-- do code later so methods stay in-order with methodBlobs
	for i,method in ipairs(self.methods) do
		if method.code then
			local cblob = WriteBlobLE()
			for _,inst in ipairs(method.code) do
				local lo = assert.index(opForInstName, inst[1])
				local instDesc = assert.index(instDescForOp, lo)
				cblob:writeu1(lo)
				instDesc.write(inst, cblob, self)
				assert.eq(0, bit.band(#cblob, 1))
			end
			method.codeData = cblob:compile()
		end

		if method.tries then
			for _,try in ipairs(method.tries) do
				for _,addrPair in ipairs(try) do
					addrPair.typeIndex = addType(addrPair.type)
				end
			end
		end
	end
--DEBUG:print('came up with '..#self.methodBlobs..' unique method signatures')


	-- now to extract out uniques from classes, fields, methods, methods.code
	for _,class in ipairs(self.classes) do
		class.thisClassIndex = addType(class.thisClass)
--DEBUG:print('adding class thisClass', class.thisClass, class.thisClassIndex)
		class.accessFlags = getFlagsFromObj(class, classAccessFlags)
--DEBUG:print('adding class accessFlags', class.accessFlags)
		class.superClassIndex = addType(class.superClass)
--DEBUG:print('adding class superclass', class.superClass, class.superClassIndex)
		class.interfaceIndex = addTypeList(class.interfaces)
		class.sourceFileIndex = addString(class.sourceFile)
		-- then annotations
		-- then classDataOfs
		-- then staticValueOfs

		-- classes will need # static and # non-static fields
		-- and # direct (aka static|private|ctor) and # non-direct methods
	end



	self.map = table()
	self.map:insert{type='header_item', count=1, offset=0}

	-- ok now all constants are accounted for ... start writing
	local blob = WriteBlobLE()

	local function align(n)
		blob:writeString(('\0'):rep((n - (#blob % n)) % n))
	end

	blob:writeString('dex\n')
	blob:writeString('\x30\x33\x39\0')

	local checksumOfs = #blob
	blob:writeu4(0)	-- space for checksum, write it once we're finished

	local sha1Ofs = #blob
	blob:writeString(('\0'):rep(20))	-- space for sha1, write it once we're finished

	-- ... or not, or make a blob for everything but the header.  would that work or would i have to factor in offsets to every struct's offsets i wrote?
	local fileSizeOfs = #blob
	blob:writeu4(0)	-- space for file size, write it once we're finished

	local headerSizeOfs = #blob
	blob:writeu4(0)	-- space for header size

	blob:writeu4(0x12345678)	-- endian tag
	blob:writeu4(0)		-- num links
	blob:writeu4(0)		-- link ofs

	local mapOfsOfs = #blob
	blob:writeu4(0)

	blob:writeu4(#self.strings)
	local stringOfsOfs = #blob
	blob:writeu4(0)

	blob:writeu4(#self.types)
	local typeOfs = #blob
	blob:writeu4(0)

	blob:writeu4(#self.protos)
	local protoOfs = #blob
	blob:writeu4(0)

	blob:writeu4(#self.fieldBlobs)
	local fieldOfs = #blob
	blob:writeu4(0)

	blob:writeu4(#self.methodBlobs)
	local methodOfs = #blob
	blob:writeu4(0)

	blob:writeu4(#self.classes)
	local classOfs = #blob
	blob:writeu4(0)

	local datasOfs = #blob
	blob:writeu4(0)	-- numDatas
	blob:writeu4(0)	-- datasOfs

	-- fill in header size
	ffi.cast('uint32_t*', blob.data.v + headerSizeOfs)[0] = #blob

--do return blob:compile() end

	local stringOfs
	if #self.strings > 0 then
		align(4)
		-- fill in the string-offset-to-offsets location ... which is redundantly the header size as well ...
		ffi.cast('uint32_t*', blob.data.v + stringOfsOfs)[0] = #blob
		self.map:insert{type='string_id_item', offset=#blob, count=#self.strings}
		-- after header comes string_id_list ... i'm guessing that means first the offsets to string data, next the string data itself?
		-- looks like from the dex file i'm reading that the offsets-to-offsets come first,
		--  then the offsets to string data comes much much later in the file.
		--  maybe in the "support data" section?
		stringOfs = #blob
		-- write placeholders for offsets
		for i=0,#self.strings-1 do
			blob:writeu4(0)
		end
	end

	-- fill in the type offsets
	if #self.types > 0 then
		align(4)
		ffi.cast('uint32_t*', blob.data.v + typeOfs)[0] = #blob
		self.map:insert{type='type_id_item', offset=#blob, count=#self.types}
		for i,typeData in ipairs(self.types) do
			assert.len(typeData, 4)	-- should be already serialized
			blob:writeString(typeData)
		end
	end

	-- fill in protos ... notice, proto arg lists probably go in that generic data clump
	local protoDefOfs
	if #self.protos > 0 then
		align(4)
		ffi.cast('uint32_t*', blob.data.v + protoOfs)[0] = #blob
		self.map:insert{type='proto_id_item', offset=#blob, count=#self.protos}
		protoDefOfs = #blob
		for i,proto in ipairs(self.protos) do
			-- proto+8 is the args offset, which will need to be replaced later
			assert.len(proto, 12)
			blob:writeString(proto)
		end
	end

	-- fill in fields
	if #self.fieldBlobs > 0 then
		align(4)
		ffi.cast('uint32_t*', blob.data.v + fieldOfs)[0] = #blob
		self.map:insert{type='field_id_item', offset=#blob, count=#self.fieldBlobs}
		for i,field in ipairs(self.fieldBlobs) do
			assert.len(field, 8)
			blob:writeString(field)
		end
	end

	-- fill in methods
	if #self.methodBlobs > 0 then
		align(4)
		ffi.cast('uint32_t*', blob.data.v + methodOfs)[0] = #blob
		self.map:insert{type='method_id_item', offset=#blob, count=#self.methodBlobs}
		for i,method in ipairs(self.methodBlobs) do
--DEBUG:print('writing method', i-1, require 'ext.string'.hex(method))
			assert.len(method, 8)
			blob:writeString(method)
		end
	end

	-- fill in classdata
	assert.gt(#self.classes, 0) 	-- otherwise why are we here...
	align(4)
--DEBUG:print('write classDataOfs', #blob)
	ffi.cast('uint32_t*', blob.data.v + classOfs)[0] = #blob
	self.map:insert{type='class_def_item', offset=#blob, count=#self.classes}
	local classDefOfs = #blob
	for i,class in ipairs(self.classes) do
local startOfs = #blob
--DEBUG:print('writing class thisClassIndex', class.thisClassIndex)
		blob:writeu4(class.thisClassIndex)
--DEBUG:print('writing class accessFlags', class.accessFlags)
		blob:writeu4(class.accessFlags)
--DEBUG:print('writing class superClassIndex', class.superClassIndex)
		blob:writeu4(class.superClassIndex)
--DEBUG:print('writing class interfaceIndex', class.interfaceIndex)
		blob:writeu4(class.interfaceIndex)	-- fill in interface-offset later
--DEBUG:print('writing class sourceFileIndex', class.sourceFileIndex)
		blob:writeu4(class.sourceFileIndex)
		blob:writeu4(0)	-- fill in annotation-offset later
		blob:writeu4(0)	-- fill in data-offset later
		blob:writeu4(0)	-- fill in static-value-offset later
assert.eq(startOfs + sizeOfClass, #blob)	-- TODO structs ...
	end

	-- keep track of where the headers structures end
	local datasStartOfs = #blob

	-- TODO fill in call sites here
	-- align(4)

	-- TODO fill in method handles here
	-- align(4)

	-- now fill in extra data ...

	-- after writing everything else, cirrrrcle back and fill in 'stringOfs' and write the string data into 'stringOfs'
	if #self.strings > 0 then
		self.map:insert{type='string_data_item', offset=#blob, count=#self.strings}
		for i,s in ipairs(self.strings) do
			local ptr = ffi.cast('uint32_t*', blob.data.v + stringOfs + 4 * (i-1))
--DEBUG:local from = ptr[0]
			ptr[0] = #blob
--DEBUG:print('changing string data item from', from, 'to', #blob)
			blob:writeUleb128(#s)
			blob:writeString(s)
		end
	end

	-- now fill in proto def type lists
	if #self.typeLists > 0 then
		align(4)
		self.map:insert{type='type_list', offset=#blob, count=#self.typeLists}
		local typeListOfs = table()
		for i,typeList in ipairs(self.typeLists) do
--DEBUG:print('writing typeList ofs', #blob, 'data', string.hex(typeList))
			typeListOfs[i] = #blob
			blob:writeString(typeList)
		end
		-- now replace all proto type list indexes with offsets
		for i=0,#self.protos-1 do
			local protoArgTypeListPtr = ffi.cast('uint32_t*', blob.data.v + protoDefOfs + 8 + sizeOfProto * i)
			if protoArgTypeListPtr[0] ~= 0 then
--DEBUG:local from = protoArgTypeListPtr[0]
				protoArgTypeListPtr[0] = assert.index(typeListOfs, protoArgTypeListPtr[0])
--DEBUG:print('changing protoArgTypeListPtr from', from, 'to', protoArgTypeListPtr[0])
			end
		end
		-- now replace all class interfaceIndexes
		for i=0,#self.classes-1 do
			local classInterfaceTypeListPtr = ffi.cast('uint32_t*', blob.data.v + classDefOfs + 12 + sizeOfClass * i)
			if classInterfaceTypeListPtr[0] ~= 0 then
--DEBUG:local from = classInterfaceTypeListPtr[0]
				classInterfaceTypeListPtr[0] = assert.index(typeListOfs, classInterfaceTypeListPtr[0])
--DEBUG:print('changing classInterfaceTypeListPtr from', from, 'to', classInterfaceTypeListPtr[0])
			end
		end
	end

	-- now fill in the class data's method data's instruction data ... before I fill in the method data's code offset as a uleb128 which is going to vary based on its size...
	align(4)
	local codeItemOfs = #blob
	local codeItemCount = 0
	-- I've asseretd method == self.methods[method.methodIndex+1]
	for _,method in ipairs(self.methods) do
		if method.codeData then
			codeItemCount = codeItemCount + 1
			-- save for later for class data
			method.codeOfs = #blob
			blob:writeu2(method.maxRegs or 0)
			blob:writeu2(method.regsIn or 0)
			blob:writeu2(method.regsOut or 0)
			blob:writeu2(method.tries and #method.tries or 0)
			blob:writeu4(0)	-- debugInfoOfs
			blob:writeu4(bit.rshift(#method.codeData, 1))	-- instructions size in uint16_t's
			blob:writeString(method.codeData)

			if bit.band(3, #blob) == 2 then blob:writeu2(0) end
			assert.eq(bit.band(3, #blob), 0, "#blob supposed to be 4-byte aligned")

			if method.tries then
				for _,try in ipairs(method.tries) do
					blob:writeu4(try.startAddr or 0)
					blob:writeu2(try.numInsts or 0)
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
						blob:writeUleb128(addrPair.typeIndex)
						blob:writeUleb128(addrPair.addr)
					end
					if try.catchAllAddr then
						blob:writeUleb128(try.catchAllAddr)
					end
				end
			end
		end
	end

	align(4)
	-- if we wrote anything, insert a map entry
	if codeItemCount > 0 then
		self.map:insert{type='code_item', offset=codeItemOfs, count=codeItemCount }
	end

	-- now fill in class data
	local classDataOfs = #blob
	local classDataCount = 0
	for classIndex,class in ipairs(self.classes) do
		-- per-class
		-- collect all fields that are static vs instance
		local staticFieldIndexes = table()	-- 1-based
		local instanceFieldIndexes = table()	-- 1-based
		for i,field in ipairs(self.fields) do
			if field.class == class.thisClass
			and field.accessFlags
			and field.accessFlags ~= 0
			then
				if field.isStatic then
					staticFieldIndexes:insert(i)
				else
					instanceFieldIndexes:insert(i)
				end
			end
		end

		-- collect all methods that are direct vs virtual
		local directMethodIndexes = table() 	-- 1-based
		local virtualMethodIndexes = table()	-- 1-based
--DEBUG:print('class data checking '..#self.methods..' methods')
		for i,method in ipairs(self.methods) do
			if method.class == class.thisClass
			and (
				(method.accessFlags and method.accessFlags ~= 0)
				or (method.codeOfs and method.codeOfs ~= 0)
			) then
				if method.isStatic
				or method.isPrivate
				or method.isConstructor
				then
--DEBUG:print('class data adding method '..i..' to direct')
					directMethodIndexes:insert(i)
				else
--DEBUG:print('class data adding method '..i..' to virtual')
					virtualMethodIndexes:insert(i)
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
			local classDataPtr = ffi.cast('uint32_t*', blob.data.v + classDefOfs + 24 + (classIndex-1) * sizeOfClass)
--DEBUG:local from = classDataPtr[0]
			classDataPtr[0] = #blob
--DEBUG:print('changing classDataPtr from', from, 'to', #blob)

			blob:writeUleb128(#staticFieldIndexes)
			blob:writeUleb128(#instanceFieldIndexes)
			blob:writeUleb128(#directMethodIndexes)
			blob:writeUleb128(#virtualMethodIndexes)

			local function writeFields(fieldIndexes)
				local lastFieldIndex = 1	-- from 1-based to 0-based
				for _,fieldIndex in ipairs(fieldIndexes) do
					blob:writeUleb128(fieldIndex - lastFieldIndex)
					blob:writeUleb128(self.fields[fieldIndex].accessFlags)
					lastFieldIndex = fieldIndex
				end
			end
			writeFields(staticFieldIndexes)
			writeFields(instanceFieldIndexes)

			local function writeMethods(methodIndexes)
				local lastMethodIndex = 1	-- from 1-based to 0-based
				for _,methodIndex in ipairs(methodIndexes) do
--DEBUG:print('writing class data for method', methodIndex-1)
					blob:writeUleb128(methodIndex - lastMethodIndex)
					local method = self.methods[methodIndex]
					blob:writeUleb128(method.accessFlags)
					-- I guess this means I better already have written the code offset data
					blob:writeUleb128(method.codeOfs or 0)
					lastMethodIndex = methodIndex
				end
			end
			writeMethods(directMethodIndexes)
			writeMethods(virtualMethodIndexes)
		end
	end
	if classDataCount > 0 then
		self.map:insert{type='class_data_item', offset=classDataOfs, count=classDataCount }
	end

	-- TODO link data last?

	-- only after everything, write the map data
	if #self.map > 0 then	-- should always be true
		align(4)
		self.map:insert{type='map_list', offset=#blob, count=1}
		local ptr = ffi.cast('uint32_t*', blob.data.v + mapOfsOfs)
--DEBUG:local from = ptr[0]
		ptr[0] = #blob
--DEBUG:print('changing mapOfs from', from, 'to', #blob)		
		blob:writeu4(#self.map)
		for _,entry in ipairs(self.map) do
			blob:writeu2((assert.index(mapListTypeForName, entry.type)))
			blob:writeu2(0)	-- unused
			blob:writeu4(entry.count)
			blob:writeu4(entry.offset)
		end
	end

	-- finally write the data section,
	-- which starts after the header's tables and ends here
	local ptr = ffi.cast('uint32_t*', blob.data.v + datasOfs)
--DEBUG:local from = ptr[0]
	ptr[0] = datasStartOfs
--DEBUG:print('changing datasStart from', from, 'to', ptr[0])
	local ptr = ffi.cast('uint32_t*', blob.data.v + datasOfs + 4)
--DEBUG:local from = ptr[0]
	ptr[0] = #blob - datasStartOfs
--DEBUG:print('changing datasOfs from', from, 'to', ptr[0])
	local ptr = ffi.cast('uint32_t*', blob.data.v + fileSizeOfs)
--DEBUG:local from = ptr[0]
	ptr[0] = #blob
--DEBUG:print('changing fileSize from', from, 'to', ptr[0])
	-- TODO done?

	-- TODO remove temp write fields?

	return blob:compile()
end

return JavaASMDex
