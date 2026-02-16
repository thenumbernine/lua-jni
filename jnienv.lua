local class = require 'ext.class'
local assert = require 'ext.assert'
local string = require 'ext.string'
local vector = require 'stl.vector-lua'
local JavaClass = require 'java.class'
local prims = require 'java.util'.prims
local getJNISig = require 'java.util'.getJNISig


local JNIEnv = class()
JNIEnv.__name = 'JNIEnv'

function JNIEnv:init(ptr)
	self.ptr = assert.type(ptr, 'cdata', "expected a JNIEnv*")
	self.classesLoaded = {}


	-- save this up front
	local java_lang_Class = self:findClass'java/lang/Class'

	-- TODO a way to cache method names, but we've got 3 things to identify them by: name, signature, static
	java_lang_Class.java_lang_Class_getName = java_lang_Class:getMethod{
		name = 'getName',
		sig = {'java/lang/String'},
	}
end

function JNIEnv:getVersion()
	return self.ptr[0].GetVersion(self.ptr)
end

function JNIEnv:findClass(classpath)
	local classObj = self.classesLoaded[classpath]
	if not classObj then
		local classptr = self.ptr[0].FindClass(self.ptr, classpath)
		if classptr == nil then
			error('failed to find class '..tostring(classpath))
		end
		classObj = JavaClass{
			env = self,
			ptr = classptr,
			classpath = classpath,
		}
		self.classesLoaded[classpath] = classObj
	end
	return classObj
end

function JNIEnv:newStr(s, len)
	assert(type(s) == 'string' or type(s) == 'cdata', 'expected string or cdata')
	local jstring
	if len then
		if type(s) == 'string' then
			-- string + length, manually convert to jchar
			local jstr = vector('jchar', len)
			for i=0,len-1 do
				jstr.v[i] = s:byte(i+1)
			end
			jstring = self.ptr[0].NewString(self.ptr, jstr.v, len)
		else
			-- cdata + len, use as-is
			jstring = self.ptr[0].NewString(self.ptr, s, len)
		end
	else
		-- assume it's a lua string or char* cdata
		jstring = self.ptr[0].NewStringUTF(self.ptr, s)
	end
	if jstring == nil then error("NewString failed") end
	local resultClassPath = 'java/lang/String'
	local JavaObject = require 'java.object'
	return JavaObject.createObjectForClassPath(
		resultClassPath, {
			env = self,
			ptr = jstring,
			classpath = resultClassPath,
		}
	)
end

local newArrayForType = prims:mapi(function(name)
	return 'New'..name:sub(1,1):upper()..name:sub(2)..'Array', name
end):setmetatable(nil)

-- jtype is a primitive or a classname
function JNIEnv:newArray(jtype, length, objInit)
	local field = newArrayForType[jtype] or 'NewObjectArray'
	local obj
	if field == 'NewObjectArray' then
		-- TODO only expect classpath, or should I give an option for a JavaClass or a jclass?
		local jclassObj = self:findClass(jtype)
		-- TODO objInit as JavaObject, but how to encode null?
		-- am I going to need a java.null placeholder object?
		obj = self.ptr[0].NewObjectArray(self.ptr, length, jclassObj.ptr, objInit)
	else
		obj = self.ptr[0][field](self.ptr, length)
	end

	-- now for each prim, JNI has a separate void* type for use with each its methods for primitive getters and setters ...
	-- TODO THIS CLASSPATH WON'T MATCH NON-ARRAY CLASSPATHS
	-- their classpath is java/lang/String or whatever
	-- this one will, for the same, be Ljava/lang/string;
	-- ...
	-- so I wiil send it jtype[], 
	-- but now the JavaObject classpath wouldn't match its getClass():getName() ...
	-- TODO switch over all stored .classpath's to JNI-sig name qualifiers.
	local resultClassPath = jtype..'[]'
	local JavaObject = require 'java.object'
	return JavaObject.createObjectForClassPath(
		resultClassPath, {
			env = self,
			ptr = obj,
			classpath = resultClassPath,
			-- how to handle classpaths of primitives ....
			-- java as a langauge is a bit of a mess
			elemClassPath = jtype,
		}
	)
end

function JNIEnv:__tostring()
	return self.__name..'('..tostring(self.ptr)..')'
end

JNIEnv.__concat = string.concat

return JNIEnv
