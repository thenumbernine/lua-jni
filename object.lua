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

function JavaObject:__tostring()
	return self.__name..'('
		..tostring(self.classpath)
		..' '
		..tostring(self.ptr)
		..')'
end

JavaObject.__concat = string.concat

-- static helper function for getting the correct JavaObject subclass depending on the classpath
function JavaObject.getWrapper(classpath)
	if classpath == 'java/lang/String' then
		-- TODO I *could* fully-qualify all these in some directory namespace, that'd be the Java thing to do ....
		return require 'java.string'
	end
	return JavaObject
end

function JavaObject.createObjectForClassPath(classpath, args)
	return JavaObject.getWrapper(classpath)(args)
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
	return self:getMethod{
		name = 'toString',
		sig = {'java/lang/String'},
	}(self) 
end

return JavaObject
