local ffi = require 'ffi'
local class = require 'ext.class'
local assert = require 'ext.assert'
local string = require 'ext.string'
local table = require 'ext.table'
local vector = require 'stl.vector-lua'
local JavaClass = require 'java.class'
local JavaObject = require 'java.object'
local prims = require 'java.util'.prims
local getJNISig = require 'java.util'.getJNISig
local sigStrToObj = require 'java.util'.sigStrToObj


local bootstrapClasses = {
	['java.lang.Class'] = true,
	['java.lang.reflect.Field'] = true,
	['java.lang.reflect.Method'] = true,
}


local JNIEnv = class()
JNIEnv.__name = 'JNIEnv'

function JNIEnv:init(ptr)
	self._ptr = assert.type(ptr, 'cdata', "expected a JNIEnv*")
	self._classesLoaded = {}

	-- always keep this non-nil for __index's sake
	self._dontCheckExceptions = false

	-- save these up front
	-- must match bootstrapClasses for the subsequent class cache build to not cause a stack overflow
	-- TODO better would be to just not make/use the cache until after building these classes and methods
	-- we need these for later:
	-- TODO a way to cache method names, but we've got 3 things to identify them by: name, signature, static
	local java_lang_Class = self:_class'java.lang.Class'
	java_lang_Class._java_lang_Class_getName = assert(java_lang_Class:_method{
		name = 'getName',
		sig = {'java.lang.String'},
	})
	java_lang_Class._java_lang_Class_getMethods = assert(java_lang_Class:_method{
		name = 'getMethods',
		sig = {'java.lang.reflect.Method[]'},
	})
	java_lang_Class._java_lang_Class_getFields = assert(java_lang_Class:_method{
		name = 'getFields',
		sig = {'java.lang.reflect.Field[]'},
	})
	
	local java_lang_reflect_Field = self:_class'java.lang.reflect.Field'
	java_lang_reflect_Field._java_lang_reflect_Field_getName = assert(java_lang_reflect_Field:_method{
		name = 'getName',
		sig = {'java.lang.String'},
	})
	
	-- only now that we got these methods can we do this
	local java_lang_reflect_Method = self:_class'java.lang.reflect.Method'
--DEBUG:print('JNIEnv:init java_lang_reflect_Method', java_lang_reflect_Method)	
	java_lang_reflect_Method._java_lang_reflect_Method_getName = assert(java_lang_reflect_Method:_method{
		name = 'getName',
		sig = {'java.lang.String'},
	})
	
--DEBUG:print("JNIEnv._classesLoaded['java.lang.Class']", self._classesLoaded['java.lang.Class'])
assert.eq(java_lang_Class._classpath, 'java.lang.Class')
--DEBUG:print('!!! saved java_lang_Class._java_lang_Class_getName')

	-- only setup reflection after all fields and methods for setting up reflection are grabbed
	java_lang_Class:_setupReflection()
	java_lang_reflect_Field:_setupReflection()
	java_lang_reflect_Method:_setupReflection()
end

function JNIEnv:_class(classpath)
--DEBUG:print('JNIEnv:_class', classpath)
	self:_checkExceptions()

	local classObj = self._classesLoaded[classpath]
--DEBUG:if classObj then assert.eq(classObj._classpath, classpath) end
--DEBUG:print('for', classpath, 'got', classObj)
	if not classObj then
--DEBUG:print('***JNIENV*** _class making new', classpath)
		-- FindClass wants /-separator
		local slashClassPath = classpath:gsub('%.', '/')
		local jclass = self._ptr[0].FindClass(self._ptr, slashClassPath)
		if jclass == nil then
			-- I think this throws an exception?
			local ex = self:_exceptionOccurred()
			return nil, 'failed to find class '..tostring(classpath), ex
		end
		classObj = self:_saveJClassForClassPath{
			ptr = jclass,
			classpath = classpath,
		}
		assert(classObj)
	end

	self:_checkExceptions()

	return classObj
end

-- makes a JavaClass object for a jclass pointer
-- saves it in _classesLoaded
-- used by JNIENV:_class and JavaObject:_class
function JNIEnv:_saveJClassForClassPath(args)
	local classpath = args.classpath
--DEBUG:print('*** JNIEnv saving '..classpath)
	args.env = self
	local classObj = JavaClass(args)

	-- maybe do this in the ctor
	-- don't do bootstrapClasses here or we'll get stack overflow from JNIEnv:init
	if not bootstrapClasses[classpath] then
		classObj:_setupReflection()
	end

	self._classesLoaded[classpath] = classObj
assert.eq(classObj._classpath, classpath)
	return classObj
end

-- get a jclass pointer for a jobject pointer
function JNIEnv:_getObjClass(objPtr)
	return self._ptr[0].GetObjectClass(self._ptr, objPtr)
end

-- get a classpath for a jobject pointer
function JNIEnv:_getObjClassPath(objPtr)
	local jclass = self:_getObjClass(objPtr)
	local java_lang_Class = self:_class'java.lang.Class'
	local sigstr = java_lang_Class._java_lang_Class_getName(jclass)
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


function JNIEnv:_version()
	return self._ptr[0].GetVersion(self._ptr)
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
	local resultClassPath = 'java.lang.String'
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

-- jtype is a primitive or a classpath
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

-- check-and-return exceptions
function JNIEnv:_exceptionOccurred()
	local e = self._ptr[0].ExceptionOccurred(self._ptr)
	if e == nil then return nil end

	if self._dontCheckExceptions then
		error("java exception in exception handler")
	end
	assert(not self._dontCheckExceptions)
	self._dontCheckExceptions = true

	self._ptr[0].ExceptionClear(self._ptr)

	local classpath = self:_getObjClassPath(e)
	local result = JavaObject._createObjectForClassPath(
		classpath,
		{
			env = self,
			ptr = e,
			classpath = classpath,
		}
	)

	self._dontCheckExceptions = false

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

	self._dontCheckExceptions = false

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

	-- don't build namespaces off private vars
	if k:match'^_' then
print('JNIEnv.__index', k, "I am reserving underscores for private variables.  You were about to invoke a jnienv classname resolve")
print(debug.traceback())
		return
	end

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

	-- dont' allow writes
	setmetatable(self, table(Name, {
		__newindex = function(k,v)
			error("namespace object is write-protected")
		end,
	}):setmetatable(nil))
end

function Name:__tostring()
	return 'Name('..rawget(self, '_name')..'.*'..')'
end

Name.__concat = string.concat

function Name:__index(k)
	v = rawget(Name, k)
	if v ~= nil then return v end

	local env = rawget(self, '_env')
	local classpath = rawget(self, '_name')..'.'..k
	local cl = env:_class(classpath)
	if cl then return cl end

--DEBUG:print('Name __index', k, 'classpath', classpath)
	return Name{env=env, name=classpath}
end

return JNIEnv
