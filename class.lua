local class = require 'ext.class'
local assert = require 'ext.assert'
local string = require 'ext.string'
local table = require 'ext.table'
local JavaMethod = require 'java.method'
local getJNISig = require 'java.util'.getJNISig

local JavaClass = class()
JavaClass.__name = 'JavaClass'

function JavaClass:init(args)
	self.env = assert.index(args, 'env')
	self.ptr = assert.index(args, 'ptr')
	self.classpath = assert.index(args, 'classpath')
end

--[[
args:
	name
	sig
		= table of args as slash-separated classpaths,
		first arg is return type
	static = boolean
--]]
function JavaClass:getMethod(args)
	assert.type(args, 'table')
	local funcname = assert.type(assert.index(args, 'name'), 'string')
	local static = args.static
	local sig = assert.type(assert.index(args, 'sig'), 'table')
	local sigstr = getJNISig(sig)
--DEBUG:print('sigstr', sigstr)

	local method
	if static then
		method = self.env.ptr[0].GetStaticMethodID(self.env.ptr, self.ptr, funcname, sigstr)
	else
		method = self.env.ptr[0].GetMethodID(self.env.ptr, self.ptr, funcname, sigstr)
	end
	if method == nil then
		error("failed to find "..tostring(funcname)..' '..tostring(sigstr))
	end
	return JavaMethod{
		env = self.env,
		class = self,
		ptr = method,
		sig = sig,
		static = static,
	}
end

-- calls in java `class.getName()`
function JavaClass:getName()
	return self.env:findClass'java/lang/Class'
		.java_lang_Class_getName(self)
end

function JavaClass:__tostring()
	return self.__name..'('
		..tostring(self.classpath)
		..' '
		..tostring(self.ptr)
		..')'
end

JavaClass.__concat = string.concat

return JavaClass
