local ffi = require 'ffi'
local class = require 'ext.class'
local assert = require 'ext.assert'
local string = require 'ext.string'
local vector = require 'stl.vector-lua'
local JavaClass = require 'java.class'
local JavaObject = require 'java.object'
local prims = require 'java.util'.prims
local getJNISig = require 'java.util'.getJNISig


local JNIEnv = class()
JNIEnv.__name = 'JNIEnv'

function JNIEnv:init(ptr)
	self._ptr = assert.type(ptr, 'cdata', "expected a JNIEnv*")
	self._classesLoaded = {}


	-- save this up front
	local java_lang_Class = self:_class'java/lang/Class'

	-- TODO a way to cache method names, but we've got 3 things to identify them by: name, signature, static
	java_lang_Class.java_lang_Class_getName = java_lang_Class:getMethod{
		name = 'getName',
		sig = {'java/lang/String'},
	}
end

function JNIEnv:_version()
	return self._ptr[0].GetVersion(self._ptr)
end

function JNIEnv:_class(classpath)
	local classObj = self._classesLoaded[classpath]
	if not classObj then
		local classptr = self._ptr[0].FindClass(self._ptr, classpath)
		if classptr == nil then
			error('failed to find class '..tostring(classpath))
		end
		classObj = JavaClass{
			env = self,
			ptr = classptr,
			classpath = classpath,
		}
		self._classesLoaded[classpath] = classObj
	end
	return classObj
end

function JNIEnv:_str(s, len)
	assert(type(s) == 'string' or type(s) == 'cdata', 'expected string or cdata')
	local jstring
	if len then
		if type(s) == 'string' then
			-- string + length, manually convert to jchar
			local jstr = vector('jchar', len)
			for i=0,len-1 do
				jstr.v[i] = s:byte(i+1)
			end
			jstring = self._ptr[0].NewString(self._ptr, jstr.v, len)
		else
			-- cdata + len, use as-is
			jstring = self._ptr[0].NewString(self._ptr, s, len)
		end
	else
		-- assume it's a lua string or char* cdata
		jstring = self._ptr[0].NewStringUTF(self._ptr, s)
	end
	if jstring == nil then error("NewString failed") end
	local resultClassPath = 'java/lang/String'
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
function JNIEnv:_newArray(jtype, length, objInit)
	local field = newArrayForType[jtype] or 'NewObjectArray'
	local obj
	if field == 'NewObjectArray' then
		-- TODO only expect classpath, or should I give an option for a JavaClass or a jclass?
		local jclassObj = self:_class(jtype)
		-- TODO objInit as JavaObject, but how to encode null?
		-- am I going to need a java.null placeholder object?
		obj = self._ptr[0].NewObjectArray(self._ptr, length, jclassObj._ptr, objInit)
	else
		obj = self._ptr[0][field](self._ptr, length)
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

-- get a jclass pointer for a jobject pointer
function JNIEnv:_getObjClass(objPtr)
	return self._ptr[0].GetObjectClass(self._ptr, objPtr)
end

-- get a classname for a jobject pointer
function JNIEnv:_getObjClassPath(objPtr)
	local jclass = self:_getObjClass(objPtr)
	local java_lang_Class = self:_class'java/lang/Class'
	local classpath = java_lang_Class.java_lang_Class_getName(jclass)
	return classpath, jclass
end

function JNIEnv:_exceptionOccurred()
	local e = self._ptr[0].ExceptionOccurred(self._ptr)
	if e == nil then return nil end

	local classpath = self:_getObjClassPath(e)
	return JavaObject.createObjectForClassPath(
		classpath, 
		{
			env = self,
			ptr = e,
			classpath = classpath,
		}
	)
end

function JNIEnv:_checkExceptions()
	local ex = self:_exceptionOccurred()
	if ex then error('JVM '..ex) end
end

-- putting _luaToJavaArgs here so it can auto-convert some objects like strings

function JNIEnv:_luaToJavaArg(arg, sig)
	local t = type(arg)
	if t == 'table' then 
		-- assert it is a cdata
		return arg._ptr 
	elseif t == 'string' then
		return self:_str(arg)._ptr
	elseif t == 'cdata' then
		return arg
	elseif t == 'number' then
		-- TODO will vararg know how to convert things?
		-- TODO assert sig is a primitive
		return ffi.new('j'..sig, arg)
	end
	error("idk how to convert arg from Lua type "..t)
end


function JNIEnv:_luaToJavaArgs(sigIndex, sig, ...)
	if select('#', ...) == 0 then return end
	return self:_luaToJavaArg(..., sig[sigIndex]), 
		self:_luaToJavaArgs(sigIndex+1, sig, select(2, ...))
end

function JNIEnv:__tostring()
	return self.__name..'('..tostring(self._ptr)..')'
end

JNIEnv.__concat = string.concat

return JNIEnv
