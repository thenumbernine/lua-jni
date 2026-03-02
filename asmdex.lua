local ffi = require 'ffi'
local class = require 'ext.class'
local assert = require 'ext.assert'
local string = require 'ext.string'
local ReadBlob = require 'java.blob'.ReadBlob
local WriteBlob = require 'java.blob'.WriteBlob

local JavaASMDex = class()
JavaASMDex.__name = 'JavaASMDex'

-- same as JavaASMClass
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
	local blob = ReadBlob(data)
	blob.littleEndian = true	-- by default
	assert.eq(blob:readString(4), 'dex\n')
	local version = blob:readString(4)	-- 3 text chars of numbers with null term ...
print('version', string.hex(version))
	local checksum = blob:readu4()
print('checksum', bit.tohex(checksum, 8))
	local sha1sig = blob:readString(20)

print('sha1sig', string.hex(sha1sig))
	local filesize = blob:readu4()
print('filesize', bit.tohex(filesize, 8))
	local headersize = blob:readu4()
print('headersize', bit.tohex(headersize, 8))
	local endian = blob:readu4()
print('endian', bit.tohex(endian, 8))
	if endian == 0x78563412 then
		-- then do I flip size and checksum as well?
		blob.littleEndian = false
	elseif endian == 0x12345678 then
		-- safe
	else
		io.stderr:write('!!! WARNING !!! endian is a bad value: 0x'..bit.tohex(endian, 8)..', something else will probably go wrong.\n')
	end
	assert.eq(filesize, #data, "filesize didn't match")	-- when does size not equal #data?

	local linkSize = blob:readu4()
	local linkOfs = blob:readu4()
print('link size', bit.tohex(linkSize, 8),'ofs', bit.tohex(linkOfs, 8))

	local mapOfs = blob:readu4()
print('map ofs', bit.tohex(mapOfs, 8))

	-- string offset points to a list of uint32_t's which point to the string data
	-- ... which start with a uleb128 prefix
	local stringIdSize = blob:readu4()
	local stringIdOfs = blob:readu4()
print('stringId size', bit.tohex(stringIdSize, 8),'ofs', bit.tohex(stringIdOfs, 8))

	-- list of uint32 idss into string table?
	local typeIdSize = blob:readu4()
	local typeIdOfs = blob:readu4()
print('typeId size', bit.tohex(typeIdSize, 8),'ofs', bit.tohex(typeIdOfs, 8))

	--[[
	proto points to:
		uint32_t string index of short-form signature
		uint32_t type-ID index of return type
		uint32_t offset into "type list" (where?)
	--]]
	local protoIdSize = blob:readu4()
	local protoIdOfs = blob:readu4()
print('protoId size', bit.tohex(protoIdSize, 8),'ofs', bit.tohex(protoIdOfs, 8))

	--[[

	--]]
	local fieldIdSize = blob:readu4()
	local fieldIdOfs = blob:readu4()
print('fieldId size', bit.tohex(fieldIdSize, 8),'ofs', bit.tohex(fieldIdOfs, 8))

	--[[
		uint16 index into type IDs of class
		uint16 index into protoIDs for method signature
		uint32 index into stringIDs for method name
	--]]
	local methodIdSize = blob:readu4()
	local methodIdOfs = blob:readu4()
print('methodId size', bit.tohex(methodIdSize, 8),'ofs', bit.tohex(methodIdOfs, 8))

	local classDefSize = blob:readu4()
	local classDefOfs = blob:readu4()
print('classDef size', bit.tohex(classDefSize, 8),'ofs', bit.tohex(classDefOfs, 8))

	local dataSize = blob:readu4()
	local dataOfs = blob:readu4()
print('data size', bit.tohex(dataSize, 8),'ofs', bit.tohex(dataOfs, 8))
end

return JavaASMDex
