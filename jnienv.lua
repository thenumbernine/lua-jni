require 'java.ffi.java'	-- just does ffi.cdef
local class = require 'ext.class'
local assert = require 'ext.assert'
local JavaClass = require 'java.class'

local JavaEnv = class()
JavaEnv.__name = 'JavaEnv'

function JavaEnv:init(ptr)
	self.ptr = assert.type(ptr, 'cdata', "expected a JNIEnv*")
end

function JavaEnv:getVersion()
	return self.ptr[0].GetVersion(self.ptr)
end

function JavaEnv:findClass(classpath)
	local classptr = self.ptr[0].FindClass(self.ptr, classpath)
	if classptr == nil then
		error('failed to find class '..tostring(classpath))
	end
	return JavaClass{
		env = self,
		class = classptr,
	}
end

return JavaEnv
