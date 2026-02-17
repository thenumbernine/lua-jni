local ffi = require 'ffi'
local class = require 'ext.class'
local assert = require 'ext.assert'
local string = require 'ext.string'
local vector = require 'stl.vector-lua'
local JavaClass = require 'java.class'
local JavaObject = require 'java.object'
local prims = require 'java.util'.prims
local getJNISig = require 'java.util'.getJNISig
local sigStrToObj = require 'java.util'.sigStrToObj


local JNIEnv = class()
JNIEnv.__name = 'JNIEnv'

function JNIEnv:init(ptr)
	self._ptr = assert.type(ptr, 'cdata', "expected a JNIEnv*")
	self._classesLoaded = {}


	-- save this up front
	local java_lang_Class = self:_class'java/lang/Class'

	-- TODO a way to cache method names, but we've got 3 things to identify them by: name, signature, static
	java_lang_Class.java_lang_Class_getName = java_lang_Class:_method{
		name = 'getName',
		sig = {'java/lang/String'},
	}
end

function JNIEnv:_version()
	return self._ptr[0].GetVersion(self._ptr)
end

function JNIEnv:_class(classpath)

	self:_checkExceptions()

	local classObj = self._classesLoaded[classpath]
	if not classObj then
		local classptr = self._ptr[0].FindClass(self._ptr, classpath)
		if classptr == nil then
			-- I think this throws an exception?
			local ex = self:_exceptionOccurred()
			return nil, 'failed to find class '..tostring(classpath), ex
		end
		classObj = JavaClass{
			env = self,
			ptr = classptr,
			classpath = classpath,
		}
		self._classesLoaded[classpath] = classObj
	end

	self:_checkExceptions()

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
	if jstring == nil
		then error("NewString failed")
	end
	local resultClassPath = 'java/lang/String'
	return JavaObject._createObjectForClassPath(
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
	return JavaObject._createObjectForClassPath(
		resultClassPath,
		{
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
	local sigstr = java_lang_Class
		.java_lang_Class_getName(jclass)
-- wait
-- are you telling me
-- when its a prim or an array, getName returns it as a signature-qualified string
-- but when it's not, getName just returns the classpath?
-- isn't that ambiguous?
	sigstr = tostring(sigstr)
--DEBUG:print('JNIEnv:_getObjClassPath', sigstr)
	-- opposite of util.getJNISig
	local classpath = sigStrToObj(sigstr) or sigstr
--DEBUG:print('JNIEnv:_getObjClassPath', classpath)
	return classpath, jclass
end

-- check-and-return exceptions
function JNIEnv:_exceptionOccurred()
	local e = self._ptr[0].ExceptionOccurred(self._ptr)
	if e == nil then return nil end
	self._ptr[0].ExceptionClear(self._ptr)

	if self._dontCheckExceptions then
		error("java exception in exception handler")
	end

	assert(not self._dontCheckExceptions)
	self._dontCheckExceptions = true

	local classpath = self:_getObjClassPath(e)
	local result = JavaObject._createObjectForClassPath(
		classpath,
		{
			env = self,
			ptr = e,
			classpath = classpath,
		}
	)

	self._dontCheckExceptions = nil

	return result
end

-- check-and-throw exception
function JNIEnv:_checkExceptions()
	local ex = self:_exceptionOccurred()
	-- but this calls toString, which could create its own exceptions ...
	if not ex then return end

	-- let's flag our jnienv for when it should and shouldn't catch exceptions

	assert(not self._dontCheckExceptions)
	self._dontCheckExceptions = true

	local errstr = 'JVM '..ex

	self._dontCheckExceptions = nil

	error(errstr)
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


local Name = class()

function JNIEnv:__index(k)
	-- automatic, right?
	--local v = rawget(self, k)
	--if v ~= nil then return v end
	v = JNIEnv[k]
	if v ~= nil then return v end
	if k:sub(1,1) == '_' then return end	-- skip our lua fields

	-- alright this is anything not in self and not in the class
	-- do automatic namespace lookup here
	-- symbol resolution of global scope of 'k'
	-- I guess that means classes only
	local cl = self:_class(k)
	if cl then return cl end

--DEBUG:print('JNIEnv __index', k)
	return Name{env=self, name=k}
end


function Name:init(args)
	rawset(self, '_env', assert.index(args, 'env'))
	rawset(self, '_name', assert.index(args, 'name'))
end

function Name:__tostring()
	return 'Name('..rawget(self, '_name')..')'
end

Name.__concat = string.concat

function Name:__index(k)
	v = rawget(Name, k)
	if v ~= nil then return v end

	local env = rawget(self, '_env')
	local classname = rawget(self, '_name')..'/'..k
	local cl = env:_class(classname)
	if cl then return cl end

--DEBUG:print('Name __index', k, 'classname', classname)
	return Name{env=env, name=classname}
end

return JNIEnv
