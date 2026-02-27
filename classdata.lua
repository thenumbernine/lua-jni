--[[
This will represent a .class blob of data, to be used with classloaders

Right now I am lazily exploding everything.

But I'm tempted to make all lua class fields into pointers into the data blob,
and give them ffi ctype metatables for reading and writing values.
and then leave the bytecode as-is...

Then again, Java-ASM ClassWriter isn't exactly writing bytes as it goes.
A lot has to be stored and compressed upon conversion to byte array.
I might as well keep it exploded.
--]]
local ffi = require 'ffi'
local table = require 'ext.table'
local assert = require 'ext.assert'
local path = require 'ext.path'
local class = require 'ext.class'


local JavaClassData = class()
JavaClassData.__name = 'JavaClassData' 

function JavaClassData:init(data)
	if type(args) == 'string' then
		self:readData(args)	-- assume its raw data 
	end
end

-- static ctor
function JavaClassData:fromFile(filename)
	local o = JavaClassData()
	o:readData((assert(path(filename):read())))
	return o
end

local Blob = class()
function Blob:init(data)
	self.data = assert.type(data, 'string')
	self.len = #self.data
	self.ptr = ffi.cast('uint8_t*', self.data)
	self.ofs = 0
end
function Blob:read(ctype)
	local size = ffi.sizeof(ctype)
	if size + self.ofs > self.len then
		error("read past the end")
	end

	local result
	if ffi.abi'be' then
		result = ffi.cast(ffi.typeof('$*', ctype), self.ptr + self.ofs)[0]
	else -- if ffi.abi'le' then
		local tmp = ffi.typeof('$[1]', ffi.typeof(ctype))()
		local tmpb = ffi.cast('uint8_t*', tmp)
		for i=0,ffi.sizeof(ctype)-1 do
			tmpb[i] = self.ptr[self.ofs + ffi.sizeof(ctype)-1-i]
		end
		result = tmp[0]
	end
	self.ofs = self.ofs + size
	return result
end
function Blob:readString(size)
	if size + self.ofs > self.len then
		error("read past the end")
	end
	local result = ffi.string(self.ptr + self.ofs, size)
	self.ofs = self.ofs + size
	return result
end
function Blob:readBlob(size)
	return Blob(self:readString(size))
end
function Blob:readu1() return self:read'uint8_t' end
function Blob:readu2() return self:read'uint16_t' end
function Blob:readu4() return self:read'uint32_t' end
function Blob:assertDone()
	if self.ofs < self.len then
		error('still have '..(self.len-self.ofs)..' bytes remaining')
	end
end

function JavaClassData:readData(data)
	local blob = Blob(data)

	local function readAttrs(b)
		local attrCount = b:readu2()
		if attrCount == 0 then return end
		local attrs = table()
		for i=0,attrCount-1 do
			local attr = {}
			attr.nameIndex = b:readu2()	-- index into constants[]
			local length = b:readu4()
			attr.info = b:readString(length)
			attrs:insert(attr)
		end
		return attrs
	end

	local magic = blob:readu4()
	assert.eq(magic, 0xcafebabe)
	local minorVersion = blob:readu2()
	local majorVersion = blob:readu2()
	-- store version info or nah?
	local constantCount = blob:readu2()
	self.constants = table()
	do
		local skipnext
		for i=1,constantCount-1 do
			if not skipnext then
				local tag = blob:read'uint8_t'
				local constant = {index=i, tag=tag}
				if tag == 7 then		-- class
					constant.nameIndex = blob:readu2()
				elseif tag == 9			-- fieldref
				or tag == 10			-- methodref
				or tag == 11 			-- interfaceMethodRef
				then
					constant.classIndex = blob:readu2()
					constant.nameAndTypeIndex = blob:readu2()
				elseif tag == 8 then	-- string
					constant.stringIndex = blob:readu2()
				elseif tag == 3 then	-- integer
					constant.value = blob:read'int32_t'
				elseif tag == 4 then	-- float
					constant.value = blob:read'float'
				elseif tag == 5 then	-- long
					-- "all 8-byte constants take up 2 entries in the constant pool ..." wrt their data only, right? no extra tag in there right?
					constant.value = blob:read'int64_t'
					skipnext = true
				elseif tag == 6 then	-- double
					constant.value = blob:read'double'
					skipnext = true
				elseif tag == 12 then	-- nameAndType
					constant.nameIndex = blob:readu2()
					constant.descriptorIndex = blob:readu2()
				elseif tag == 1 then 	-- utf8
					local length = blob:readu2()
					constant.value = blob:readString(length)
				elseif tag == 15 then	-- methodHandle
					constant.referenceKind = blob:readu2()
					constant.referenceIndex = blob:readu2()
				elseif tag == 16 then	-- methodType
					constant.descriptorIndex = blob:readu2()
				elseif tag == 18 then	-- invokeDynamic
					constant.boostrapMethodAttrIndex = blob:readu2()
					constant.nameAndTypeIndex = blob:readu2()
				elseif tag == 19 then	-- module
					constant.nameIndex = blob:readu2()
				elseif tag == 20 then	-- package
					constant.nameIndex = blob:readu2()
				else
					error('unknown tag '..tostring(tag)..' / 0x'..bit.tohex(tag, 2)
						..' at offset 0x'..bit.tohex(ofs)
					)
				end
				self.constants:insert(constant)
			else
				self.constants:insert(false)
				skipnext = false
			end
		end
	end
	self.accessFlags = blob:readu2()
	self.thisClass = blob:readu2()
	self.superClass = blob:readu2()
	local interfaceCount = blob:readu2()
	if interfaceCount > 0 then
		self.interfaces = table()
		for i=0,interfaceCount-1 do
			local interface = blob:readu2()
			self.interfaces:insert(interface)
		end
	end
	local fieldCount = blob:readu2()
	self.fields = table()
	for i=0,fieldCount-1 do
		local field = {}
		field.accessFlags = blob:readu2()
		field.nameIndex = blob:readu2()
		field.descriptorIndex = blob:readu2()
		local attrCount = blob:readu2()
		if attrCount ~= 0 then
			assert.eq(attrCount, 1)
			field.attrNameIndex = blob:readu2()
			local length = blob:readu4()
			assert.eq(len, 2)
			field.constantValueIndex = blob:readu2()
		end
		self.fields:insert(field)
	end
	local methodCount = blob:readu2()
	self.methods = table()
	for i=0,methodCount-1 do
		local method = {}
		method.accessFlags = blob:readu2()
		method.nameIndex = blob:readu2()
		method.descriptorIndex = blob:readu2()
		local attrCount = blob:readu2()
		if attrCount ~= 0 then
			assert.eq(attrCount, 1)
			local code = {}
			code.nameIndex = blob:readu2()
			local attrLen = blob:readu4()
			local cblob = blob:readBlob(attrLen)
			code.maxStack = cblob:readu2()
			code.maxLocals = cblob:readu2()
			local codeLength = cblob:readu4()
			code.code = cblob:readString(codeLength)
			local exceptionCount = cblob:readu2()
			if exceptionCount > 0 then
				code.exceptions = table()
				for i=0,exceptionCount-1 do
					local ex = {}
					ex.startPC = cblob:readu2()
					ex.endPC = cblob:readu2()
					ex.handlerPC = cblob:readu2()
					ex.catchType = cblob:readu2()
					code.exceptions:insert(ex)
				end
			end
			code.attrs = readAttrs(cblob)
			cblob:assertDone()
			method.code = code
		end
		self.methods:insert(method)
	end

	self.attrs = readAttrs(blob)

	blob:assertDone()
end

return JavaClassData
