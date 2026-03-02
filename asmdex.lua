local ffi = require 'ffi'
local class = require 'ext.class'
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
	assert.eq(blob:readString(8), 'dex\n035\0')
	local checksum = blob:readu4()
	local sha1sig = blob:readString(20)
	local size = blob:readu4()
	local endian = blob:readu4()
	if endian == 0x78563412 then
		-- then do I flip size and checksum as well?
		blob.littleEndian = false
	end
	assert.eq(size, #data, "size didn't match")	-- when does size not equal #data?
	local linkSize = blob:readu4()
	local linkOfs = blob:readu4()
	local mapOfs = blob:readu4()

	-- string offset points to a list of uint32_t's which point to the string data
	-- ... which start with a uleb128 prefix
	local stringIdsSize = blob:readu4()
	local stringIdsOfs = blob:readu4()

	-- list of uint32 idss into string table?
	local typeIdsSize = blob:readu4()
	local typeIdsOfs = blob:readu4()

	--[[
	proto points to:
		uint32_t string index of short-form signature
		uint32_t type-ID index of return type
		uint32_t offset into "type list" (where?)
	--]]
	local protoIdsSize = blob:readu4()
	local protoIdsOfs = blob:readu4()

	--[[

	--]]
	local fieldIdsSize = blob:readu4()
	local fieldIdsOfs = blob:readu4()

	--[[
		uint16 index into type IDs of class
		uint16 index into protoIDs for method signature
		uint32 index into stringIDs for method name
	--]]
	local methodIdsSize = blob:readu4()
	local methodIdsOfs = blob:readu4()

	local classDefSize = blob:readu4()
	local classDefOfs = blob:readu4()

	local dataSize = blob:readu4()
	local dataOfs = blob:readu4()
end
