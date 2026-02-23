local ffi = require 'ffi'
local class = require 'ext.class'
local assert = require 'ext.assert'
local string = require 'ext.string'
local table = require 'ext.table'
local JavaClass = require 'java.class'
local JavaObject = require 'java.object'
local prims = require 'java.util'.prims
local infoForPrims = require 'java.util'. infoForPrims
local getJNISig = require 'java.util'.getJNISig

-- some of these overlap ctypes
local jboolean = ffi.typeof'jboolean'	-- uint8_t
local jbyte = ffi.typeof'jbyte'			-- int8_t
local jshort = ffi.typeof'jshort'		-- int16_t
local jchar = ffi.typeof'jchar'			-- uint16_t
local jint = ffi.typeof'jint'			-- int32_t
local jlong = ffi.typeof'jlong'			-- int64_t
local jfloat = ffi.typeof'jfloat'		-- float
local jdouble = ffi.typeof'jdouble'		-- double

local getPrimNameForCTypeName = {
	[tostring(jboolean)] = 'boolean',
	[tostring(jbyte)] = 'byte',
	[tostring(jshort)] = 'short',
	[tostring(jchar)] = 'char',
	[tostring(jint)] = 'int',
	[tostring(jlong)] = 'long',
	[tostring(jfloat)] = 'float',
	[tostring(jdouble)] = 'double',
}

local getUnboxedPrimitiveForClasspath = {
	['java.lang.Boolean'] = 'boolean',
	['java.lang.Char'] = 'char',
	['java.lang.Byte'] = 'byte',
	['java.lang.Short'] = 'short',
	['java.lang.Int'] = 'int',
	['java.lang.Long'] = 'long',
	['java.lang.Float'] = 'float',
	['java.lang.Double'] = 'double',
}

local getUnboxedValueGetterMethod = {
	['java.lang.Boolean'] = 'booleanValue',
	['java.lang.Char'] = 'charValue',
	['java.lang.Byte'] = 'byteValue',
	['java.lang.Short'] = 'shortValue',
	['java.lang.Int'] = 'intValue',
	['java.lang.Long'] = 'longValue',
	['java.lang.Float'] = 'floatValue',
	['java.lang.Double'] = 'doubleValue',
}

local isPrimitive = prims:mapi(function(name) return true, name end):setmetatable(nil)


local jchar_arr = ffi.typeof'jchar[?]'	-- used by JNIEnv.NewString
local JavaVM_ptr_1 = ffi.typeof'JavaVM*[1]'


local bootstrapClasses = {
	['java.lang.Class'] = true,
	['java.lang.reflect.Field'] = true,
	['java.lang.reflect.Method'] = true,
	['java.lang.reflect.Constructor'] = true,
}


local JNIEnv = class()
JNIEnv.__name = 'JNIEnv'
JNIEnv.subclass = nil
--JNIEnv.isa = nil -- TODO
--JNIEnv.isaSet = nil -- TODO

--[[
args:
	ptr = JNIEnv* cdata
	vm = vm to store (optional, to prevent it from gc'ing if we hold only the JNIEnv)
--]]
function JNIEnv:init(args)
	self._ptr = assert.type(assert.index(args, 'ptr'), 'cdata', "expected a JNIEnv*")
	self._vm = args.vm or false		-- jnienv will hold the vm just so the vm doesn't gc
	if not self._vm then
		-- make a JavaVM object around the pointer
		local jvmPtrArr = JavaVM_ptr_1()
		assert.eq(ffi.C.JNI_OK, self._ptr[0].GetJavaVM(self._ptr, jvmPtrArr))
		local jvmPtr = jvmPtrArr[0]
		if jvmPtr == nil then
			-- if I can't get the JavaVM* back then no problem, except that I can't do multithreading
			-- but for API consistentcy let's make sure it works
			error("couldn't get JavaVM* back from JNIEnv*")
		end
		local JavaVM = require 'java.vm'
		self._vm = JavaVM{ptr = jvmPtr}
	end

	self._classesLoaded = {}

	-- always keep this non-nil for __index's sake
	self._dontCheckExceptions = false
	-- don't JavaObject-wrap excpetions during startup
	self._ignoringExceptions = true

	-- save these up front
	-- must match bootstrapClasses for the subsequent class cache build to not cause a stack overflow
	-- TODO better would be to just not make/use the cache until after building these classes and methods
	-- we need these for later:
	-- TODO a way to cache method names, but we've got 3 things to identify them by: name, signature, static
	self._java_lang_Class = self:_findClass'java.lang.Class'
	self._java_lang_Class._java_lang_Class_getTypeName = assert(self._java_lang_Class:_method{
		name = 'getTypeName',
		sig = {'java.lang.String'},
	})
	self._java_lang_Class._java_lang_Class_getFields = assert(self._java_lang_Class:_method{
		name = 'getFields',
		sig = {'java.lang.reflect.Field[]'},
	})
	self._java_lang_Class._java_lang_Class_getMethods = assert(self._java_lang_Class:_method{
		name = 'getMethods',
		sig = {'java.lang.reflect.Method[]'},
	})
	self._java_lang_Class._java_lang_Class_getConstructors = assert(self._java_lang_Class:_method{
		name = 'getConstructors',
		sig = {'java.lang.reflect.Constructor[]'},
	})

	self._java_lang_reflect_Field = self:_findClass'java.lang.reflect.Field'
	self._java_lang_reflect_Field._java_lang_reflect_Field_getName = assert(self._java_lang_reflect_Field:_method{
		name = 'getName',
		sig = {'java.lang.String'},
	})
	self._java_lang_reflect_Field._java_lang_reflect_Field_getType = assert(self._java_lang_reflect_Field:_method{
		name = 'getType',
		sig = {'java.lang.Class'},
	})
	self._java_lang_reflect_Field._java_lang_reflect_Field_getModifiers = assert(self._java_lang_reflect_Field:_method{
		name = 'getModifiers',
		sig = {'int'},
	})

	-- only now that we got these methods can we do this
	self._java_lang_reflect_Method = self:_findClass'java.lang.reflect.Method'
--DEBUG:print('JNIEnv:init self._java_lang_reflect_Method', self._java_lang_reflect_Method)
	self._java_lang_reflect_Method._java_lang_reflect_Method_getName = assert(self._java_lang_reflect_Method:_method{
		name = 'getName',
		sig = {'java.lang.String'},
	})
	self._java_lang_reflect_Method._java_lang_reflect_Method_getReturnType = assert(self._java_lang_reflect_Method:_method{
		name = 'getReturnType',
		sig = {'java.lang.Class'},
	})
	self._java_lang_reflect_Method._java_lang_reflect_Method_getParameterTypes = assert(self._java_lang_reflect_Method:_method{
		name = 'getParameterTypes',
		sig = {'java.lang.Class[]'},
	})
	self._java_lang_reflect_Method._java_lang_reflect_Method_getModifiers = assert(self._java_lang_reflect_Method:_method{
		name = 'getModifiers',
		sig = {'int'},
	})

	-- so if Method and Constructor both inherit from Executable, and it has getName, getParameterTypes, getModifiers, can I just get those methods from it and use on both?
	-- or does the jmethodID not do vtable lookup?
	-- I won't risk it
	self._java_lang_reflect_Constructor = self:_findClass'java.lang.reflect.Constructor'
	self._java_lang_reflect_Constructor._java_lang_reflect_Constructor_getParameterTypes = assert(self._java_lang_reflect_Constructor:_method{
		name = 'getParameterTypes',
		sig = {'java.lang.Class[]'},
	})
	self._java_lang_reflect_Constructor._java_lang_reflect_Constructor_getModifiers = assert(self._java_lang_reflect_Constructor:_method{
		name = 'getModifiers',
		sig = {'int'},
	})

	-- now that reflection is setup, we can start JavaObject-wrapping excpetions
	assert.eq(true, self._ignoringExceptions)
	self._ignoringExceptions = false
	-- and throw away alll those field-not-found, method-not-found etc exceptions
	self:_exceptionClear()

	-- only setup reflection after all fields and methods for setting up reflection are grabbed
	-- NOTICE these are going to also ignore and clear exceptions, individually
	-- as they will do during runtime for each newly loaded class
	self._java_lang_Class:_setupReflection()
	self._java_lang_reflect_Field:_setupReflection()
	self._java_lang_reflect_Method:_setupReflection()
	self._java_lang_reflect_Constructor:_setupReflection()

	-- now that we're done bootloading, just cache String because it is useful
	self._java_lang_String = self:_findClass'java.lang.String'


	-- TODO in the J namespace, for the primitive names,
	-- should I put ffi cdata types?
	-- or the equivalent .class's in Java?
	-- I think I'll put the ffi types , because you can get to the Java classes through java.lang.Integer etc
	-- and this way the J.whatever classname maps to what the Lua args expect, including ffi data
	-- so J.int will be a jint ffi ctype
	for _,prim in ipairs(prims) do
		self._classesLoaded[prim] = infoForPrims[prim].ctype
	end
end

function JNIEnv:_findClass(classpath)
	self:_checkExceptions()

	local classObj = self._classesLoaded[classpath]
	if not classObj then
		local slashClassPath = getJNISig(classpath)
		local envptr = self._ptr
		local jclass = envptr[0].FindClass(envptr, slashClassPath)
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

-- accepts a JNI jclass cdata
-- looks up the classname
-- looks up if its loaded in Lua yet
-- ... loads it in Lua if not
-- returns the JavaClass
function JNIEnv:_getClassForJClass(jclass)
	if jclass == nil then return nil end
	local classpath = self:_getJClassClasspath(jclass)

	local classObj = self._classesLoaded[classpath]
	if not classObj then
		classObj = self:_saveJClassForClassPath{
			ptr = jclass,
			classpath = classpath,
		}
assert.eq(classObj._classpath, classpath)
	end
	return classObj
end

-- makes a JavaClass object for a jclass pointer
-- saves it in _classesLoaded
-- used by _findClass and _getClassForJClass
function JNIEnv:_saveJClassForClassPath(args)
	local classpath = args.classpath
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
	local envptr = self._ptr
	return envptr[0].GetObjectClass(envptr, objPtr)
end

-- Get a classpath for a jobject pointer
-- Only used in _exceptionOccurred
-- This is just obj:_getClass():getTypeName()
-- but with maybe a few less calls
function JNIEnv:_getObjClassPath(objPtr)
	local jclass = self:_getObjClass(objPtr)
	return self:_getJClassClasspath(jclass), jclass
end

-- Accepts JNI jclass cdata
-- returns classpath
-- uses java.lang.Class.getTypeName
function JNIEnv:_getJClassClasspath(jclass)
	local javaTypeName = self._java_lang_Class._java_lang_Class_getTypeName(jclass)
	if javaTypeName == nil then return nil end
	return tostring(javaTypeName)
end

function JNIEnv:_version()
	local envptr = self._ptr
	return envptr[0].GetVersion(envptr)
end

function JNIEnv:_str(s, len)
	assert(type(s) == 'string' or type(s) == 'cdata', 'expected string or cdata')
	local jstring
	if len then
		if type(s) == 'string' then
			-- string + length, manually convert to jchar
			local jstr = jchar_arr(len)
			for i=0,len-1 do
				jstr[i] = s:byte(i+1)
			end
			jstring = self._ptr[0].NewString(self._ptr, jstr, len)
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
	return JavaObject._createObjectForClassPath{
		env = self,
		ptr = jstring,
		classpath = resultClassPath,
	}
end

local newArrayForType = prims:mapi(function(name)
	return 'New'..name:sub(1,1):upper()..name:sub(2)..'Array', name
end):setmetatable(nil)

-- use mapi from prims so it is deterministic

local primNameForCTypes = {}
for _,name in ipairs(prims) do
	local primInfo = infoForPrims[name]
	primNameForCTypes[tostring(assert(primInfo.ctype))] = name
end

-- jtype is a primitive or a classpath
function JNIEnv:_newArray(jtype, length, objInit)

	-- if jtype is a ffi ctype then convert it back to its name
	if type(jtype) == 'cdata' then
		jtype = primNameForCTypes[tostring(jtype)] or jtype
	end

	local field = newArrayForType[jtype] or 'NewObjectArray'
	local obj
	if field == 'NewObjectArray' then
		local jclassObj = jtype
		if type(jtype) == 'string' then
			jclassObj = self:_findClass(jclassObj)
		else
			assert(JavaClass:isa(jclassObj), "JNIEnv:_newArray expects a classpath or a JavaClass object")
		end
		-- TODO objInit as JavaObject, but how to encode null?
		-- am I going to need a java.null placeholder object?
		obj = self._ptr[0].NewObjectArray(
			self._ptr,
			length,
			jclassObj._ptr,
			self:_luaToJavaArg(objInit, jclassObj._classpath)
		)
	else
		obj = self._ptr[0][field](self._ptr, length)
	end

	local resultClassPath = jtype..'[]'
	return JavaObject._createObjectForClassPath{
		env = self,
		ptr = obj,
		classpath = resultClassPath,
		-- how to handle classpaths of primitives ....
		-- java as a langauge is a bit of a mess
		elemClassPath = jtype,
	}
end

function JNIEnv:_throw(e)
	self._ptr[0].Throw(self._ptr, e._ptr)
end

-- for classes
function JNIEnv:_throwNew(cl)
	self._ptr[0].ThrowNew(self._ptr, cl._ptr)
end

function JNIEnv:_exceptionClear()
	self._ptr[0].ExceptionClear(self._ptr)
end

-- check-and-return exceptions
function JNIEnv:_exceptionOccurred()

	-- during startup, reflection on base classes, I don't want this class' mechanism to be used for repackaging exceptions
	-- while the classes they would be packaged with aren't yet fully initialized
	-- so during startup all exceptions just get deferred
	if self._ignoringExceptions then return end

	local e = self._ptr[0].ExceptionOccurred(self._ptr)
	if e == nil then return nil end

--DEBUG:print('got exception', e)
--DEBUG:print(debug.traceback())

	if self._dontCheckExceptions then
		error("java exception in exception handler")
	end
	assert(not self._dontCheckExceptions)
	self._dontCheckExceptions = true

	self:_exceptionClear()

	local classpath = self:_getObjClassPath(e)

--DEBUG:print('exception classpath', classpath)
--DEBUG:print(debug.traceback())

	local result = JavaObject._createObjectForClassPath{
		env = self,
		ptr = e,
		classpath = classpath,
	}

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

-- shorthand
function JNIEnv:_new(classObj, ...)
	if type(classObj) == 'string' then
		classObj = self:_findClass(classObj)
	end
	return classObj:_new(...)
end

-- putting _luaToJavaArgs here so it can auto-convert some objects like strings

-- returns true/false if the primitive widening is allowed, and the distance for the name resolver
local function getPrimWidening(from, to)
	-- compare unboxedArgType with sig
	-- TODO this is identical to below except i'm too lazy to consolidate it yet
	if from == 'boolean' then
		if to == 'boolean'then return true, 0
		end
	elseif from == 'byte' then
		if to == 'byte'then return true, 0
		elseif to == 'short'then return true, 1
		elseif to == 'int'then return true, 2
		elseif to == 'long'then return true, 3
		elseif to == 'float'then return true, 4
		elseif to == 'double'then return true, 5
		end
	elseif from == 'short' then
		if to == 'short'then return true, 0
		elseif to == 'int'then return true, 1
		elseif to == 'long'then return true, 2
		elseif to == 'float'then return true, 3
		elseif to == 'double'then return true, 4
		end
	elseif from == 'char' then
		if to == 'char' then return true, 0
		elseif to == 'int'then return true, 1
		elseif to == 'long'then return true, 2
		elseif to == 'float'then return true, 3
		elseif to == 'double'then return true, 4
		end
	elseif from == 'int' then
		if to == 'int'then return true, 0
		elseif to == 'long'then return true, 1
		elseif to == 'float'then return true, 2
		elseif to == 'double'then return true, 3
		end
	elseif from == 'long' then
		if to == 'long'then return true, 0
		elseif to == 'float'then return true, 1
		elseif to == 'double'then return true, 2
		end
	elseif from == 'float' then
		if to == 'float'then return true, 0
		elseif to == 'double'then return true, 1
		end
	elseif from == 'double' then
		if to == 'double'then return true, 0
		end
	end
	return false
end

-- same as below but doesnt actually convert, just returns true/false
-- used for call resolution / overload matching
function JNIEnv:_canConvertLuaToJavaArg(arg, sig)
	local t = type(arg)

-- hmm TODO auto-boxing auto-unboxing ...
-- if arg is a boxed type then convert it to its prim value / as cdata (for proper type conversion)
-- if sig is a boxed type then examine its prim type instead

	if t == 'boolean' then
		return sig == 'boolean' or sig == 'java.lang.Boolean'
	elseif t == 'table' then
		local unboxedSig = getUnboxedPrimitiveForClasspath[sig] or sig
		if isPrimitive[unboxedSig]
		and JavaObject:isa(arg)
		then
			-- if incoming is boxed type and sig is prim then yes
			local unboxedArgType = getUnboxedPrimitiveForClasspath[arg._classpath]
			if unboxedArgType then
				return getPrimWidening(unboxedArgType, unboxedSig)
			end
			return false
		end
		local nonarraybase = sig:match'^(.*)%['
		if nonarraybase then
			if isPrimitive[nonarraybase] then return false end
		end
		return (arg:_instanceof(sig))
	elseif t == 'string' then
		if isPrimitive[sig] then
			return false
		end
		local nonarraybase = sig:match'^(.*)%['
		if nonarraybase then
			if isPrimitive[nonarraybase] then return false end
		end
		return (self._java_lang_String:_isAssignableFrom(sig))
	elseif t == 'cdata' then

		-- convert ffi jni jprim to java prim
		local ct = ffi.typeof(arg)
		local ctname = tostring(ct)

		-- I'm going to spell this all out until I get it down, then I will replace it with faster rules (or would rules be faster?)
		local unboxedSig = getUnboxedPrimitiveForClasspath[sig] or sig
		local argType = getPrimNameForCTypeName[ctname]
		if argType then
			return getPrimWidening(argType, unboxedSig)
		end

		-- TODO if it's a ffi jni prim
		-- converted to a java.lang. primitive box class
		-- then true & convert below

		if ctname:match'%*' then
			-- lazy / special case for when unboxedSig=='long' only:
			-- this way I can pass ffi pointers to java longs without having to cast them to ffi pointers first.
			if sig == 'long' then
				return true
			end

			-- TODO casting from boxed types to prims? is that a thing?
			if isPrimitive[sig] then
				return false
			end

			local toClassObj = self:_findClass(sig)

			local jobject = arg
			-- how to determine if it is a class or not
			local envptr = self._ptr

			-- if its class is a java.lang.Class then use it for assignability test
			-- otherwise use its class for assignability test
			local jclassToTest
			local jclass = envptr[0].GetObjectClass(envptr, jobject)
			if jclass == self._java_lang_Class._ptr then
				jclassToTest = jobject
			else
				jclassToTest = jclass
			end

			return 0 ~= envptr[0].IsAssignableFrom(envptr, jclassToTest, toClassObj._ptr)
		end

		return false
	elseif t == 'number' then
		local unboxedSig = getUnboxedPrimitiveForClasspath[sig] or sig
		if unboxedSig then
			-- welp I don't want to discount all but doubles, like Java does...
			--getPrimWidening('double', unboxedSig)
			-- but it would be nice to get the proximity from double ...
			-- maybe I'll do reverse from byte ...
			if unboxedSig == 'double'then return true, 0
			elseif unboxedSig == 'float'then return true, 1
			elseif unboxedSig == 'long'then return true, 2
			elseif unboxedSig == 'int'then return true, 3
			elseif unboxedSig == 'short'then return true, 4
			elseif unboxedSig == 'byte'then return true, 5
			end
		end
	elseif t == 'boolean' then
		return sig == 'boolean' or sig == 'java.lang.Boolean'
	elseif t == 'nil' then
		-- wait, in java can you pass null to a primitive?  I think not ...
		return not isPrimitive[sig]
	end
	return false
end

function JNIEnv:_luaToJavaArg(arg, sig)
	local t = type(arg)
	if t == 'boolean'  then
		if sig == 'boolean' then
			return jboolean(arg)
		else
			error("can't cast boolean to "..sig)
		end
	elseif t == 'table' then
--print('arg is table, sig is', sig)
		if sig then
			-- TODO who is calling this without sig anyways?
-- ALSO TODO
-- if a function has a signature of a prim and of Object
-- and you pass it a boxed prim
-- which will resolve?
-- in fact, Object does resolve
-- so so far so good
			if isPrimitive[sig] then
				if JavaObject:isa(arg) then
					local unboxedArgType = getUnboxedPrimitiveForClasspath[arg._classpath]
					if unboxedArgType then
						local getValueField = assert.index(getUnboxedValueGetterMethod, arg._classpath)
						return arg[getValueField](arg)
					end
				end

				error("can't cast object to primitive")
			end
			local nonarraybase = sig:match'^(.*)%['
			if nonarraybase then
				if isPrimitive[nonarraybase] then
					error("can't cast object to primitive array")
				end
			end
		end
		-- assert it is a cdata
		return arg._ptr
	elseif t == 'string' then
		if isPrimitive[sig] then
			error("can't cast string to primitive")
		end
		local nonarraybase = sig:match'^(.*)%['
		if nonarraybase then
			if isPrimitive[nonarraybase] then
				error("can't cast object to primitive array")
			end
		end
		return self:_str(arg)._ptr
	elseif t == 'cdata' then
		-- leave int64's as-is to cast to jlong's
		-- TODO test for all j* prim types
		local ct = ffi.typeof(arg)
		local ctname = tostring(ct)

		-- if we are converting to a prim type
		local unboxedSig = getUnboxedPrimitiveForClasspath[sig] or sig
		local primInfo = infoForPrims[unboxedSig]
		if primInfo then
			-- if we are coming from a prim type
			if primNameForCTypes[ctname] then
				-- convert ffi ctype prim to java prim
				return primInfo.ctype(arg)
			end
			-- TODO else if we're coming from a boxed type, convert that

			-- special case, auto-convert pointers to longs
			if unboxedSig == 'long'
			and ctname:match'%*'
			then
				return arg
			end

			-- otherwise error
			error("can't convert non-primitive to primitive")
		end

		if ctname:match'%*' then
			return arg
		end

		-- cross our fingers, what's one more segfault?
		return arg
	elseif t == 'number' then
		local primInfo = infoForPrims[sig]
		if not primInfo then
			error("can't convert number to "..sig)
		end
		-- TODO will vararg know how to convert things?
		-- TODO assert sig is a primitive
		return ffi.new(primInfo.ctype, arg)
	elseif t == 'nil' then
		local primInfo = infoForPrims[sig]
		-- objects can be nil
		if not primInfo then return nil end
		return ffi.new(primInfo.ctype)
	end
	error("idk how to convert arg from Lua type "..t.." to Java type "..tostring(sig))
end

function JNIEnv:_luaToJavaArgs(sigIndex, sig, ...)
	if select('#', ...) == 0 then return end
	return self:_luaToJavaArg(..., sig[sigIndex]),
		self:_luaToJavaArgs(sigIndex+1, sig, select(2, ...))
end

function JNIEnv:_javaToLuaArg(value, returnType)
	if returnType == 'void' then return end
	if returnType == 'boolean' then
		return value ~= 0
	end
	if isPrimitive[returnType] then return value end

	-- if Java returned null then return Lua nil
	-- ... if the JNI is returning null object results as NULL pointers ...
	-- ... and the JNI itself segfaults when it gets passed a NULl that it doesn't like ...
	-- ... where else do I have to bulletproof calls to the JNI?
	if value == nil then return nil end

	-- convert / wrap the result
	return JavaObject._createObjectForClassPath{
		env = self,
		ptr = value,
		classpath = returnType,
	}
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
	local v = JNIEnv[k]
	if v ~= nil then return v end

	if type(k) ~= 'string' then return end

	-- don't build namespaces off private vars
	if k:match'^_' then
		print('JNIEnv.__index', k, "I am reserving underscores for private variables.  You were about to invoke a name resolve")
		print(debug.traceback())
		return
	end

	-- alright this is anything not in self and not in the class
	-- do automatic namespace lookup here
	-- symbol resolution of global scope of 'k'
	-- I guess that means classes only

	-- ignore exceptions while we search for the class
	self:_checkExceptions()
assert.eq(false, self._ignoringExceptions)
	self._ignoringExceptions = true
	local cl = self:_findClass(k)
assert.eq(true, self._ignoringExceptions)
	self._ignoringExceptions = false
	self:_exceptionClear()

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
	local v = rawget(Name, k)
	if v ~= nil then return v end

	-- don't build namespaces off private vars
	-- this is really here to prevent stackoverflows during __index operations
	if k:match'^_' then
		print('Name.__index', k, "I am reserving underscores for private variables.  You were about to invoke a name resolve")
		print(debug.traceback())
		return
	end

	local env = rawget(self, '_env')
	local classpath = rawget(self, '_name')..'.'..k

	-- ignore exceptions while we search for the class
	env:_checkExceptions()
assert.eq(false, env._ignoringExceptions)
	env._ignoringExceptions = true
	local cl = env:_findClass(classpath)
assert.eq(true, env._ignoringExceptions)
	env._ignoringExceptions = false
	env:_exceptionClear()

	if cl then return cl end

--DEBUG:print('Name __index', k, 'classpath', classpath)
	return Name{env=env, name=classpath}
end

return JNIEnv
