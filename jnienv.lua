local class = require 'ext.class'
local assert = require 'ext.assert'
local JavaClass = require 'java.class'

local JNIEnv = class()
JNIEnv.__name = 'JNIEnv'

function JNIEnv:init(ptr)
	self.ptr = assert.type(ptr, 'cdata', "expected a JNIEnv*")
end

function JNIEnv:getVersion()
	return self.ptr[0].GetVersion(self.ptr)
end

function JNIEnv:findClass(classpath)
	local classptr = self.ptr[0].FindClass(self.ptr, classpath)
	if classptr == nil then
		error('failed to find class '..tostring(classpath))
	end
	return JavaClass{
		env = self,
		ptr = classptr,
	}
end

function JNIEnv:getObjectClass(classObj)
	classObj = classObj.ptr or classObj
	assert.type(classObj, 'cdata')
	local classClass = self.ptr[0].GetObjectClass(self.ptr, classObj)
	return JavaClass{
		env = self,
		ptr = classClass,
	}
end

return JNIEnv
