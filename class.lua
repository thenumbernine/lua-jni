local class = require 'ext.class'
local assert = require 'ext.assert'
local string = require 'ext.string'
local table = require 'ext.table'
local JavaMethod = require 'java.method'
local getJNISig = require 'java.util'.getJNISig
local sigStrToObj = require 'java.util'.sigStrToObj

local JavaClass = class()
JavaClass.__name = 'JavaClass'

function JavaClass:init(args)
	self._env = assert.index(args, 'env')
	self._ptr = assert.index(args, 'ptr')
	self._classpath = assert.index(args, 'classpath')
end

--[[
args:
	name
	sig
		= table of args as slash-separated classpaths,
		first arg is return type
	static = boolean
--]]
function JavaClass:_method(args)
	assert.type(args, 'table')
	local funcname = assert.type(assert.index(args, 'name'), 'string')
	local static = args.static
	local sig = assert.type(assert.index(args, 'sig'), 'table')
	local sigstr = getJNISig(sig)
--DEBUG:print('sigstr', sigstr)

	local method
	if static then
		method = self._env._ptr[0].GetStaticMethodID(self._env._ptr, self._ptr, funcname, sigstr)
	else
		method = self._env._ptr[0].GetMethodID(self._env._ptr, self._ptr, funcname, sigstr)
	end
	if method == nil then
		return nil, "failed to find "..tostring(funcname)..' '..tostring(sigstr)..(static and ' static' or '')
	end
	return JavaMethod{
		env = self._env,
		class = self,
		ptr = method,
		sig = sig,
		static = static,
	}
end

-- calls in java `class.getName()`
-- notice, this matches getJNISig(classname)
-- so java/lang/String will be Ljava/lang/String;
-- and double[] will be [D
function JavaClass:_name()
	local classpath = self._env:_class'java/lang/Class'
		.java_lang_Class_getName(self)
--[[ wait, is this a classpath or a signature?
-- how come double[] arrays return [D ?
-- how come String[] arrays return [Ljava/lang/String;
-- but String returns java/lang/String ? ?!?!?!??!?
-- HOW ARE YOU SUPPOSED TO TELL A SIGNATURE VS A CLASSPATH?
print('JavaClass:_name', type(classpath), classpath)
--]]
	classpath = tostring(classpath)
	classpath = sigStrToObj(classpath) or classpath
	return classpath
end

function JavaClass:__tostring()
	return self.__name..'('
		..tostring(self._classpath)
		..' '
		..tostring(self._ptr)
		..')'
end

JavaClass.__concat = string.concat

return JavaClass
