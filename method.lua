local class = require 'ext.class'
local assert = require 'ext.assert'

local JavaMethod = class()

function JavaMethod:init(args)
	self.env = assert.index(args, 'env')
	self.class = assert.index(args, 'class')
	self.ptr = assert.index(args, 'method')
end

function JavaMethod:__call(...)
	local result = self.env.ptr[0].CallStaticObjectMethod(
		self.env.ptr,
		self.class.ptr,
		self.ptr,
		...	-- TODO convert these to whatever JNI wants
	)
	-- TODO convert / wrap the result
	return result
end

return JavaMethod
