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
	if classpath == 'java.lang.String' then
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
--DEBUG:print('	JavaObject:_class()')
	local env = self._env
	local classpath, jclass = env:_getObjClassPath(self._ptr)
--DEBUG:print('JavaObject:_class classpath='..classpath)
	--[[ always make a new one
	local classObj = env:_saveJClassForClassPath(jclass, classpath)
	--]]
	-- [[ write only if it exists
-- TODO problems FIXME
	local classObj = env._classesLoaded[classpath]
--DEBUG:if classObj then assert.eq(classObj._classpath, classpath) end
--DEBUG:print('classObj', classObj)
	if not classObj then
--DEBUG:print('!!! JavaObject._class creating JavaClass for classpath='..classpath)
		local JavaClass = require 'java.class'
		classObj = JavaClass{
			env = env,
			ptr = jclass,
			classpath = classpath,
		}
--DEBUG:print('!!! JavaObject._class overwriting '..classpath..' with classObj '..classObj)
		env._classesLoaded[classpath] = classObj
assert.eq(classObj._classpath, classpath)
	end
	--]]
	return classObj
end

-- shorthand for self:_class():_method(args)
function JavaObject:_method(args)
	return self:_class():_method(args)
end

-- shorthand
function JavaObject:_field(args)
	return self:_class():_field(args)
end

-- calls in java `obj.toString()`
function JavaObject:_javaToString()
	return tostring(self:_method{
		name = 'toString',
		sig = {'java.lang.String'},
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
