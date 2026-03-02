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
end
