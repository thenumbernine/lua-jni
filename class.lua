local class = require 'ext.class'
local assert = require 'ext.assert'
local JavaMethod = require 'java.method'

local JavaClass = class()
JavaClass.__name = 'JavaClass'

function JavaClass:init(args)
	self.env = assert.index(args, 'env')
	self.ptr = assert.index(args, 'class')
end

function JavaClass:getStaticMethod(funcname, funcsig)
	local method = self.env.ptr[0].GetStaticMethodID(self.env.ptr, self.ptr, funcname, funcsig)
	if method == nil then
		error("failed to find "..tostring(funcname)..' '..tostring(funcsig))
	end
	return JavaMethod{
		env = self.env,
		class = self,
		method = method,
	}
end

return JavaClass
