-- where I'm putting my blob read/write mechanisms that I use for asmclass and asmdex
-- maybe someday I'll turn it into a traverser that reads or writes and unify the save and load ....
local ffi = require 'ffi'
local table = require 'ext.table'
local assert = require 'ext.assert'
local class = require 'ext.class'
local vector = require 'stl.vector-lua'	-- hmm, for asmdex writing I will need to go back and write buffer contents ... this isn't technically good to do when the buffer is a string ...
local fromlua = require 'ext.fromlua'


local function castToNumberOrJPrim(value)
	if type(value) == 'number' then
		return value
	end
	if type(value) == 'cdata' then
		-- TODO rest of prims?
		-- though a few will get default cast to lua number anyways ...
		if ffi.typeof(value) == ffi.typeof'jlong'
		or ffi.typeof(value) == ffi.typeof'jdouble'
		then
			return value
		end
	end
	if type(value) == 'string' then
		return assert(fromlua(value))
	end

	error("I expected a lua number or cdata jlong or jdouble. "
		..' found type='..type(value)
		..(type(value) == 'cdata'
			and (' typeof='..tostring(ffi.typeof(value)))
			or ''
		)
		..' value='..tostring(value)
	)
end


local ReadBlob = class()
ReadBlob.littleEndian = false
function ReadBlob:init(data)
	self.data = assert.type(data, 'string')
	self.len = #self.data
	self.ptr = ffi.cast('uint8_t*', self.data)
	self.ofs = 0
end
function ReadBlob:read(ctype)
	ctype = ffi.typeof(ctype)
	local size = ffi.sizeof(ctype)
	if self.ofs < 0 then
		error("read before beginning")
	end
	if size + self.ofs > self.len then
		error("read past the end")
	end

	local result
	if ffi.abi'le' == self.littleEndian then
		result = ffi.cast(ffi.typeof('$*', ctype), self.ptr + self.ofs)[0]
	else
		local tmp = ffi.typeof('$[1]', ctype)()
		local tmpb = ffi.cast('uint8_t*', tmp)
		for i=0,ffi.sizeof(ctype)-1 do
			tmpb[i] = self.ptr[self.ofs + ffi.sizeof(ctype)-1-i]
		end
		result = tmp[0]
	end
	self.ofs = self.ofs + size
--DEBUG(@5):print('read', self.ofs, ctype, result)
	return result
end
function ReadBlob:readString(size)
	if self.ofs < 0 then
		error("read before beginning")
	end
	if size + self.ofs > self.len then
		error("read past the end")
	end
	local result = ffi.string(self.ptr + self.ofs, size)
	self.ofs = self.ofs + size
--DEBUG(@5):print('readstring', self.ofs, result)
	return result
end
function ReadBlob:readBlob(size)
	return ReadBlob(self:readString(size))
end
function ReadBlob:readu1() return self:read'uint8_t' end
function ReadBlob:readu2() return self:read'uint16_t' end
function ReadBlob:readu4() return self:read'uint32_t' end
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
function ReadBlob:readSleb128()
	local result = 0
	local shift = 0
	local byte
	for count=1,5 do
		byte = self:read'int8_t'
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
function ReadBlob:done() return self.ofs == self.len end
function ReadBlob:assertDone()
	if self.ofs < self.len then
		error('still have '..(self.len-self.ofs)..' bytes remaining')
	end
end


local WriteBlob = class()
WriteBlob.littleEndian = false
function WriteBlob:init()
	self.data = vector'uint8_t'	-- TODO luajit string.buffer ?
end
function WriteBlob:write(ctype, value)
	value = castToNumberOrJPrim(value)
--DEBUG(@5):print('write', #self.data, ctype, value)
	ctype = ffi.typeof(ctype)
	local size = ffi.sizeof(ctype)
	local result
	local data = ffi.typeof('$[1]', ctype)()
	data[0] = value
	local ofs = #self.data
	self.data:resize(ofs + size)
	if ffi.abi'le' == self.littleEndian then
		ffi.copy(self.data.v + ofs, data, size)
	else
		local ptr = ffi.cast('uint8_t*', data)
		for i=0,size-1 do
			self.data.v[ofs + i] = ptr[size-1-i]
		end
	end
end
function WriteBlob:writeu1(...) return self:write('uint8_t', ...) end
function WriteBlob:writeu2(...) return self:write('uint16_t', ...) end
function WriteBlob:writeu4(...) return self:write('uint32_t', ...) end
function WriteBlob:writeString(s)
	local ofs = #self.data
--DEBUG(@5):print('writestring', ofs, s)
	local n = #s
	self.data:resize(ofs + n)
	ffi.copy(self.data.v + ofs, s, n)
end

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
	castToNumberOrJPrim = castToNumberOrJPrim,
}
