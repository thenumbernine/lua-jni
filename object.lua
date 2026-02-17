local class = require 'ext.class'
local assert = require 'ext.assert'
local string = require 'ext.string'

local JavaObject = class()
JavaObject.__name = 'JavaObject'

function JavaObject:init(args)
	self._env = assert.index(args, 'env')
	self._ptr = assert.index(args, 'ptr')

	-- TODO detect if not provided?
	self._classpath = assert.index(args, 'classpath')
end

-- static helper
function JavaObject._getLuaClassForClassPath(classpath)
	if classpath == 'java/lang/String' then
		return require 'java.string'
	-- I can't tell how I should format the classpath
	elseif classpath:match'^%[' then
		error("dont' use jni signatures for classpaths")
		return require 'java.array'
	elseif classpath:match'%[%]$' then
		return require 'java.array'
	end
	return JavaObject
end

-- static helper function for getting the correct JavaObject subclass depending on the classpath
function JavaObject._createObjectForClassPath(classpath, args)
	return JavaObject._getLuaClassForClassPath(classpath)(args)
end

-- gets a JavaClass wrapping the java call `obj._class()`
function JavaObject:_class()
	local classpath, jclass = self._env:_getObjClassPath(self._ptr)
	local JavaClass = require 'java.class'
	return JavaClass{
		env = self._env,
		ptr = jclass,
		classpath = classpath,
	}
end

-- shorthand for self:_class():_method(args)
function JavaObject:_method(args)
	return self:_class():_method(args)
end

-- calls in java `obj.toString()`
function JavaObject:_javaToString()
	return tostring(self:_method{
		name = 'toString',
		sig = {'java/lang/String'},
	}(self))
end

function JavaObject:_getDebugStr()
	return self.__name..'('
		..tostring(self._classpath)
		..' '
		..tostring(self._ptr)
		..')'
end

function JavaObject:__tostring()
	return self:_javaToString()
end

JavaObject.__concat = string.concat

return JavaObject
