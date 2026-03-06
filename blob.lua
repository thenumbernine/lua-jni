-- where I'm putting my blob read/write mechanisms that I use for asmclass and asmdex
-- maybe someday I'll turn it into a traverser that reads or writes and unify the save and load ....
require 'java.ffi.jni'	-- jlong jdouble
local ffi = require 'ffi'
local table = require 'ext.table'
local assert = require 'ext.assert'
local class = require 'ext.class'
local vector = require 'stl.vector-lua'	-- hmm, for asmdex writing I will need to go back and write buffer contents ... this isn't technically good to do when the buffer is a string ...
local fromlua = require 'ext.fromlua'


local int8_t = ffi.typeof'int8_t'
local uint8_t = ffi.typeof'uint8_t'
local uint8_t_ptr = ffi.typeof'uint8_t*'
local int16_t = ffi.typeof'int16_t'
local uint16_t = ffi.typeof'uint16_t'
local int32_t = ffi.typeof'int32_t'
local uint32_t = ffi.typeof'uint32_t'
local jlong = ffi.typeof'jlong'
local jdouble = ffi.typeof'jdouble'


-- TODO I could combine ReadBlob and WriteBlob into a File-like class that just has a rw head at some location...
local ReadBlob = class()
ReadBlob.littleEndian = false
function ReadBlob:init(data)
	local n = #data
	self.data = vector(uint8_t, n)
	ffi.copy(self.data.v, data, n)
	self.ofs = 0
end
function ReadBlob:read(ctype)
	ctype = ffi.typeof(ctype)
	local size = ffi.sizeof(ctype)
	if self.ofs < 0 then
		error("read before beginning")
	end
	if size + self.ofs > #self.data then
		error("read past the end")
	end

	local result
	if ffi.abi'le' == self.littleEndian then
		result = ffi.cast(ffi.typeof('$*', ctype), self.data.v + self.ofs)[0]
	else
		local tmp = ffi.typeof('$[1]', ctype)()
		local tmpb = ffi.cast(uint8_t_ptr, tmp)
		for i=0,ffi.sizeof(ctype)-1 do
			tmpb[i] = self.data.v[self.ofs + ffi.sizeof(ctype)-1-i]
		end
		result = tmp[0]
	end
	self.ofs = self.ofs + size
--DEBUG(@5):print('read', self.ofs, ctype, result)
	--assert.type(result, 'cdata')
	return result
end
function ReadBlob:readString(size)
	if self.ofs < 0 then
		error("read before beginning")
	end
	if size + self.ofs > #self.data then
		error("read past the end")
	end
	local result = ffi.string(self.data.v + self.ofs, size)
	self.ofs = self.ofs + size
--DEBUG(@5):print('readstring', self.ofs, result)
	return result
end
function ReadBlob:reads1() return self:read(int8_t) end
function ReadBlob:readu1() return self:read(uint8_t) end
function ReadBlob:reads2() return self:read(int16_t) end
function ReadBlob:readu2() return self:read(uint16_t) end
function ReadBlob:reads4() return self:read(int32_t) end
function ReadBlob:readu4() return self:read(uint32_t) end
function ReadBlob:readSleb128()
	local result = 0
	local shift = 0
	local byte
	for count=1,5 do
		byte = self:reads1()
		if byte == -1 then error("unexpected EOF") end
		result = bit.bor(result, bit.lshift(bit.band(byte, 0x7f), shift))
		shift = shift + 7
		if 0 == bit.band(byte, 0x80) then break end
	end
	if bit.band(byte, 0x40) ~= 0 then
		result = bit.bor(result, bit.lshift(bit.bnot(0), shift))
	end
	return result
end
function ReadBlob:readUleb128()
	local result = 0
	local shift = 0
	for count=1,5 do
		local byte = self:readu1()
		result = bit.bor(result, bit.lshift(bit.band(byte, 0x7f), shift))
		shift = shift + 7
		if 0 == bit.band(byte, 0x80) then break end
	end
	return result
end
function ReadBlob:done() return self.ofs == #self.data end
function ReadBlob:assertDone()
	if self.ofs < #self.data then
		error('still have '..(#self.data-self.ofs)..' bytes remaining')
	end
end


local WriteBlob = class()
WriteBlob.littleEndian = false
function WriteBlob:init()
	self.data = vector(uint8_t)	-- TODO luajit string.buffer ?
end
function WriteBlob:write(value)
	assert.type(value, 'cdata')
	local ctype = ffi.typeof(value)
	local ofs = #self.data
--DEBUG(@5):print('write', ofs, ctype, value)
	local size = ffi.sizeof(ctype)
	local result
	local data = ffi.typeof('$[1]', ctype)(value)
	self.data:resize(ofs + size)
	if ffi.abi'le' == self.littleEndian then
		ffi.copy(self.data.v + ofs, data, size)
	else
		local ptr = ffi.cast(uint8_t_ptr, data)
		for i=0,size-1 do
			self.data.v[ofs + i] = ptr[size-1-i]
		end
	end
end
function WriteBlob:writeString(s)
	local ofs = #self.data
--DEBUG(@5):print('writestring', ofs, s)
	local n = #s
	self.data:resize(ofs + n)
	ffi.copy(self.data.v + ofs, s, n)
end
function WriteBlob:writes1(value) return self:write(int8_t(value)) end
function WriteBlob:writeu1(value) return self:write(uint8_t(value)) end
function WriteBlob:writes2(value) return self:write(int16_t(value)) end
function WriteBlob:writeu2(value) return self:write(uint16_t(value)) end
function WriteBlob:writes4(value) return self:write(int32_t(value)) end
function WriteBlob:writeu4(value) return self:write(uint32_t(value)) end
function WriteBlob:writes8(value) return self:write(int64_t(value)) end
function WriteBlob:writeu8(value) return self:write(uint64_t(value)) end
function WriteBlob:writeUleb128(value)
	for count=1,5 do
		local byte = bit.band(0x7f, value)
		value = bit.rshift(value, 7)
		if value ~= 0 then byte = bit.bor(0x80, byte) end
		self:writeu1(byte)
		if value == 0 then break end
	end
end
function WriteBlob:writeSleb128()
	for count=1,5 do
		local byte = bit.band(0x7f, value)
		value = bit.rshift(value, 7)
		if (value == 0 and bit.band(byte, 0x40) == 0)
		or (value == -1 and bit.band(byte, 0x40) ~= 0)
		then
			self:writeu1(byte)
			break
		end
		byte = bit.band(0x80, byte)
		self:writeu1(byte)
	end
end
function WriteBlob:__len() return #self.data end

function WriteBlob:compile()
	return self.data:dataToStr()
end

local ReadBlobLE = ReadBlob:subclass()
ReadBlobLE.littleEndian = true

local WriteBlobLE = WriteBlob:subclass()
WriteBlobLE.littleEndian = true

return {
	ReadBlob = ReadBlob,
	WriteBlob = WriteBlob,
	ReadBlobLE = ReadBlobLE,
	WriteBlobLE = WriteBlobLE,
}
