local class = require 'ext.class'
local assert = require 'ext.assert'
local string = require 'ext.string'

local JavaObject = class()
JavaObject.__name = 'JavaObject'

function JavaObject:init(args)
	self.env = assert.index(args, 'env')
	self.ptr = assert.index(args, 'ptr')

	-- TODO detect if not provided?
	self.classpath = assert.index(args, 'classpath')
end

-- static helper function for getting the correct JavaObject subclass depending on the classpath
function JavaObject.createObjectForClassPath(classpath, args)
	if classpath == 'java/lang/String' then
		return require 'java.string'(args)
	-- I can't tell how I should format the classpath
	elseif classpath:match'^%[' 
	or classpath:match'%[%]$'
	then
		return require 'java.array'(args)
	end
	return JavaObject(args)
end

-- gets a JavaClass wrapping the java call `obj.getClass()`
function JavaObject:getClass()
	local JavaClass = require 'java.class'
	local jclass = self.env.ptr[0].GetObjectClass(self.env.ptr, self.ptr)

	-- alright now my ctor expects a classpath to go along with our jclass
	-- but we don't have one yet
	local java_lang_Class = self.env:findClass'java/lang/Class'
	-- dot-separated or slash-separated?
	-- which is the standard?
	local classpath = java_lang_Class.java_lang_Class_getName(jclass)

	return JavaClass{
		env = self.env,
		ptr = jclass,
		classpath = classpath,
	}
end

-- shorthand for self:getClass():getMethod(args)
function JavaObject:getMethod(args)
	return self:getClass():getMethod(args)
end

-- calls in java `obj.toString()`
function JavaObject:getJavaToString()
	return tostring(self:getMethod{
		name = 'toString',
		sig = {'java/lang/String'},
	}(self))
end

function JavaObject:getDebugStr()
	return self.__name..'('
		..tostring(self.classpath)
		..' '
		..tostring(self.ptr)
		..')'
end

function JavaObject:__tostring()
	return self:getJavaToString()
end

JavaObject.__concat = string.concat

return JavaObject
