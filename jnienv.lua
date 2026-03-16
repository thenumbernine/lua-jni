local jni = require 'java.ffi.jni'		-- get cdefs
local ffi = require 'ffi'
local class = require 'ext.class'
local assert = require 'ext.assert'
local string = require 'ext.string'
local table = require 'ext.table'
local JavaClass = require 'java.class'
local JavaObject = require 'java.object'

local java_util = require 'java.util'
local prims = java_util.prims
local infoForPrims = java_util.infoForPrims
local getJNISig = java_util.getJNISig
local sigStrToObj = java_util.sigStrToObj
local toSlashSepName = java_util.toSlashSepName

local jboolean = ffi.typeof'jboolean'	-- uint8_t
local jbyte = ffi.typeof'jbyte'			-- int8_t
local jshort = ffi.typeof'jshort'		-- int16_t
local jchar = ffi.typeof'jchar'			-- uint16_t
local jint = ffi.typeof'jint'			-- int32_t
local jlong = ffi.typeof'jlong'			-- int64_t
local jfloat = ffi.typeof'jfloat'		-- float
local jdouble = ffi.typeof'jdouble'		-- double

local getPrimNameForCTypeName = table.map(
	infoForPrims,
	function(info)
		return info.name, tostring(info.ctype)
	end
):setmetatable(nil)

local getUnboxedPrimitiveForClasspath = table.map(
	infoForPrims,
	function(info)
		return info.name, info.boxedType
	end
):setmetatable(nil)

local getUnboxedValueGetterMethod = table.map(
	infoForPrims,
	function(info)
		return info.name..'Value', info.boxedType
	end
):setmetatable(nil)

local isPrimitive = prims:mapi(function(name) return true, name end):setmetatable(nil)


local jchar_arr = ffi.typeof'jchar[?]'	-- used by JNIEnv.NewString
local JavaVM_ptr_1 = ffi.typeof'JavaVM*[1]'


local bootstrapClasses = {
	['java.lang.Class'] = true,
	['java.lang.Object'] = true,
	['java.lang.reflect.Field'] = true,
	['java.lang.reflect.Method'] = true,
	['java.lang.reflect.Constructor'] = true,
}


local JNIEnv = class()
JNIEnv.__name = 'JNIEnv'
JNIEnv.subclass = nil
--[[
alright because
1) I'm messing with JNIEnv's __index to do classpath lookup
2) I'm trying to preserve the Lua-based OOP functions
so I want to allow JNIEnv:isa() to work.
--JNIEnv.isa = nil -- has to be here
--JNIEnv.isaSet = nil -- " " " "
So I'm going to leave JNIEnv.isa and JNI.isaSet.
But I'll just dodge them in the object's __index metamethod.
--]]


--[[
args:
	ptr = JNIEnv* cdata
	vm = vm to store (optional, to prevent it from gc'ing if we hold only the JNIEnv)
	usingAndroidJNI =
		My old Android Java doesn't like signature for JNIEnv->FindClass
		But signature-based lookups are the most flexible, especially for finding array classes, so I'm making it the default.
		So Android Java has to pass this extra flag.
--]]
function JNIEnv:init(args)
	self._ptr = assert.type(assert.index(args, 'ptr'), 'cdata', "expected a JNIEnv*")
	self._vm = args.vm or false		-- jnienv will hold the vm just so the vm doesn't gc
	self._usingAndroidJNI = not not args.usingAndroidJNI
	if not self._vm then
		-- make a JavaVM object around the pointer
		local jvmPtrArr = JavaVM_ptr_1()
		assert.eq(ffi.C.JNI_OK, self:_getJavaVM(jvmPtrArr))
		local jvmPtr = jvmPtrArr[0]
		if jvmPtr == nil then
			-- if I can't get the JavaVM* back then no problem, except that I can't do multithreading
			-- but for API consistentcy let's make sure it works
			error("couldn't get JavaVM* back from JNIEnv*")
		end
		local JavaVM = require 'java.vm'
		self._vm = JavaVM{
			ptr = jvmPtr,
			jniEnv = self,	-- don't make a new JNIEnv wrapper
			usingAndroidJNI = self._usingAndroidJNI,
		}
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
	self._java_lang_Class = self:import'java.lang.Class'
	self._java_lang_Class._java_lang_Class_getTypeName = assert(self._java_lang_Class:_method{
		name = 'getTypeName',
		sig = {'java.lang.String'},
	})
	-- or not since I need this in JavaClass's ctor, and chicken and egg...
	self._java_lang_Class._java_lang_Class_getModifiers = assert(self._java_lang_Class:_method{
		name = 'getModifiers',
		sig = {'int'},
	})
	self._java_lang_Class._java_lang_Class_getDeclaredFields = assert(self._java_lang_Class:_method{
		name = 'getDeclaredFields',
		sig = {'java.lang.reflect.Field[]'},
	})
	self._java_lang_Class._java_lang_Class_getDeclaredMethods = assert(self._java_lang_Class:_method{
		name = 'getDeclaredMethods',
		sig = {'java.lang.reflect.Method[]'},
	})
	self._java_lang_Class._java_lang_Class_getDeclaredConstructors = assert(self._java_lang_Class:_method{
		name = 'getDeclaredConstructors',
		sig = {'java.lang.reflect.Constructor[]'},
	})
	--[[
	self._java_lang_Class._java_lang_Class_getDeclaredClasses = assert(self._java_lang_Class:_method{
		name = 'getDeclaredClasses',
		sig = {'java.lang.Class[]'},
	})
	--]]
	self._java_lang_Class._java_lang_Class_getInterfaces = assert(self._java_lang_Class:_method{
		name = 'getInterfaces',
		sig = {'java.lang.Class[]'},
	})

	self._java_lang_reflect_Field = self:import'java.lang.reflect.Field'
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
	self._java_lang_reflect_Method = self:import'java.lang.reflect.Method'
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
	self._java_lang_reflect_Constructor = self:import'java.lang.reflect.Constructor'
	self._java_lang_reflect_Constructor._java_lang_reflect_Constructor_getParameterTypes = assert(self._java_lang_reflect_Constructor:_method{
		name = 'getParameterTypes',
		sig = {'java.lang.Class[]'},
	})
	self._java_lang_reflect_Constructor._java_lang_reflect_Constructor_getModifiers = assert(self._java_lang_reflect_Constructor:_method{
		name = 'getModifiers',
		sig = {'int'},
	})

	self._java_lang_Object = self:import'java.lang.Object'
	self._java_lang_Object._java_lang_Object_toString = assert(self._java_lang_Object:_method{
		name = 'toString',
		sig = {'java.lang.String'},
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
	self._java_lang_Object:_setupReflection()

	-- now that we're done bootloading, just cache String because it is useful
	self._java_lang_String = self:import'java.lang.String'


	-- TODO in the J namespace, for the primitive names,
	-- should I put ffi cdata types?
	-- or the equivalent .class's in Java?
	-- I think I'll put the ffi types , because you can get to the Java classes through java.lang.Integer etc
	-- and this way the J.whatever classname maps to what the Lua args expect, including ffi data
	-- so J.int will be a jint ffi ctype
	for _,prim in ipairs(prims) do
		self._classesLoaded[prim] = infoForPrims[prim].ctype
	end
	self._classesLoaded.void = ffi.typeof'void'
end

---------------- JNI C API but with minimal arg tweaks ----------------

-- use this wth a jobject
function JNIEnv:throw(e)
	return self:_throw(e._ptr)
end

---------------- SUPPORT FUNCTIONS ----------------

function JNIEnv:import(classpath)
	self:_checkExceptions()

	local classObj = self._classesLoaded[classpath]
	if not classObj then
		--[[ NOTICE NOTICE NOTICE
		-- using a JNI signature, i.e. "Ljava/lang/ClassName;", is the most flexible here
		-- however Google's Android Java is dumb and can't handle that,
		-- it only wants "java/lang/ClassName"
		-- but this method can't handle arrays-of-classes and primitives.

Wait it just got even dumber on Google's part.

Here's desktop compat. It makes sense.  It uses either slash-separated, or L-slash-semicolon JNI-signature-style , but only L-slash-semicolon for array-types:

	> J:_findClass'java/lang/Object'		<- cdata<void *>: 0x5d3ba1cccaf8
	> J:_findClass'java/lang/Object[]'		<- cdata<void *>: NULL
	> J:_findClass'Ljava/lang/Object;'		<- cdata<void *>: 0x5d3ba1cccb00
	> J:_findClass'[Ljava/lang/Object;'		<- cdata<void *>: 0x5d3ba1cccb08

Here's Android.  It's nonsense.  It *must* be slash, without L-slash-semicolon, *except* for arrays:

	> J:_findClass'java/lang/Object'		<- works
	> J:_findClass'java/lang/Object[]'		<- segfaults
	> J:_findClass'Ljava/lang/Object;'		<- segfaults
	> J:_findClass'[Ljava/lang/Object;'		<- WORKS ... ??!??!?

I think nobody of competence came up with Android's spec.  Especially their segfault-on-error.
		--]]
		local slashClassPath
		if self._usingAndroidJNI then
			-- android has, only for arrays, use JNI-style L-slash-semicolon
			-- but for all others, explicitly do not.
			if classpath:match'%]$' then
				slashClassPath = getJNISig(classpath)
			else
				slashClassPath = classpath:gsub('%.', '/')
			end
		else
			slashClassPath = getJNISig(classpath)
		end
		local jclass = self:_findClass(slashClassPath)
		if jclass == nil then
			-- I think this throws an exception?
			local ex = self:_getException()
			return nil, 'failed to find class '..tostring(classpath)..': '..tostring(ex), ex
		end
		classObj = self:_saveJClassForClassPath{
			ptr = jclass,
			classpath = classpath,
		}
		self:_deleteLocalRef(jclass)
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
function JNIEnv:_fromJClass(jclass)
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
-- used by import and _fromJClass
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

-- Get a classpath for a jobject pointer
-- Only used in _getException
-- This is just obj:_getClass():getTypeName()
-- but with maybe a few less calls
function JNIEnv:_getObjClassPath(objPtr)
	local jclass = self:_getObjectClass(objPtr)
	local classpath = self:_getJClassClasspath(jclass)
	self:_deleteLocalRef(jclass)
	return classpath
end

-- Accepts JNI jclass cdata
-- returns classpath
-- uses java.lang.Class.getTypeName
function JNIEnv:_getJClassClasspath(jclass)
	local jstringClasspath = self:_callObjectMethod(jclass, self._java_lang_Class._java_lang_Class_getTypeName._ptr)
	if jstringClasspath == nil then return nil end
	local classpath = self:_fromJString(jstringClasspath)
	self:_deleteLocalRef(jstringClasspath)

	-- if Class.getType returns it in JNI style (which I guess it should?  but it isn't in Android?) then convert it back.
	if classpath:match';$' then
		classpath = sigStrToObj(classpath)
	end
	return classpath
end

function JNIEnv:_fromJObject(jobject)
	if jobject == nil then return nil end
	local classpath = self:_getObjClassPath(jobject)
	return JavaObject._createObjectForClassPath{
		env = self,
		ptr = jobject,
		classpath = classpath,
	}
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
			jstring = self:_newString(jstr, len)
		else
			-- cdata + len, use as-is
			jstring = self:_newString(s, len)
		end
	else
		-- assume it's a lua string or char* cdata
		jstring = self:_newStringUTF(s)
	end
	if jstring == nil
		then error("NewString failed")
	end
	local obj = JavaObject._createObjectForClassPath{
		env = self,
		ptr = jstring,
		classpath = 'java.lang.String',
	}
	self:_deleteLocalRef(jstring)
	return obj
end

-- convert Java String to Lua string
function JNIEnv:_fromJString(jstring)
	local sptr = self:_getStringUTFChars(jstring, nil)
	if sptr == nil then return nil end
	local luastr = ffi.string(sptr)
	self:_releaseStringUTFChars(jstring, sptr)
	return luastr
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

-- jtype can be:
-- - a string: is a primitive or a classpath
-- - a JavaClass object
function JNIEnv:_newArray(jtype, length, objInit)

	-- if jtype is a ffi ctype then convert it back to its name
	if type(jtype) == 'cdata' then
		jtype = primNameForCTypes[tostring(jtype)] or jtype
	end

	local field = newArrayForType[jtype] or 'NewObjectArray'
	local jobject
	if field == 'NewObjectArray' then
		local jclassObj = jtype
		if type(jtype) == 'string' then
			jclassObj = self:import(jclassObj)
		else
			assert(JavaClass:isa(jclassObj), "JNIEnv:_newArray expects a classpath or a JavaClass object")
			jtype = jclassObj._classpath
		end
		-- TODO objInit as JavaObject, but how to encode null?
		-- am I going to need a java.null placeholder object?
		jobject = self:_newObjectArray(
			length,
			jclassObj._ptr,
			self:_luaToJavaArg(objInit, jclassObj._classpath)
		)
	else
		jobject = self._ptr[0][field](self._ptr, length)
	end

	local resultClassPath = jtype..'[]'
	local obj = JavaObject._createObjectForClassPath{
		env = self,
		ptr = jobject,
		classpath = resultClassPath,
		-- how to handle classpaths of primitives ....
		-- java as a langauge is a bit of a mess
		elemClassPath = jtype,
	}
	self:_deleteLocalRef(jobject)
	return obj
end

-- check-and-return exceptions
function JNIEnv:_getException()

	-- during startup, reflection on base classes, I don't want this class' mechanism to be used for repackaging exceptions
	-- while the classes they would be packaged with aren't yet fully initialized
	-- so during startup all exceptions just get deferred
	if self._ignoringExceptions then return end

	local jthrowable = self:_exceptionOccurred()
	if jthrowable == nil then return nil end

--DEBUG:print('got exception', jthrowable)
--DEBUG:print(debug.traceback())

	if self._dontCheckExceptions then
		io.stderr:write("WARNING! java exception in exception handler\n")
		io.stderr:write(debug.traceback(),'\n')
		return
	end
	assert(not self._dontCheckExceptions)
	self._dontCheckExceptions = true

	self:_exceptionClear()

--DEBUG:print('exception classpath', self:_getObjClassPath(jthrowable))
--DEBUG:print(debug.traceback())

	local result = self:_fromJObject(jthrowable)
	self:_deleteLocalRef(jthrowable)

	self._dontCheckExceptions = false

	return result
end

-- check-and-throw exception
function JNIEnv:_checkExceptions()
	local ex = self:_getException()
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
		classObj = self:import(classObj)
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
--DEBUG:print('arg type', t)

-- hmm TODO auto-boxing auto-unboxing ...
-- if arg is a boxed type then convert it to its prim value / as cdata (for proper type conversion)
-- if sig is a boxed type then examine its prim type instead

	if t == 'boolean' then
		return sig == 'boolean' or sig == 'java.lang.Boolean'
	elseif t == 'table' then
--DEBUG:print('arg classpath', arg._classpath)
		-- before testing unboxing / widening / etc, just see if it matches
		if arg._classpath == sig then return true end

		local unboxedSig = getUnboxedPrimitiveForClasspath[sig] or sig
--DEBUG:print('unboxedSig', unboxedSig)
		if isPrimitive[unboxedSig]
		and JavaObject:isa(arg)
		then
--DEBUG:print('testing unboxed sig...')
			-- if incoming is boxed type and sig is prim then yes
			local unboxedArgType = getUnboxedPrimitiveForClasspath[arg._classpath]
--DEBUG:print('unboxedArgType', unboxedArgType)
			if unboxedArgType then
				return getPrimWidening(unboxedArgType, unboxedSig)
			end

			return false
		end

		-- if we're matching an object to a primitive[] ...
		local nonarraybase = sig:match'^(.*)%['
--DEBUG:print('nonarraybase', nonarraybase)
		if nonarraybase then
--DEBUG:print('isPrimitive[nonarraybase]', isPrimitive[nonarraybase])
			if isPrimitive[nonarraybase] then
				return false
			end
		end
--DEBUG:print('(arg:instanceof(sig))', (arg:instanceof(sig)))
		return (arg:instanceof(sig))
	elseif t == 'string' then
		if isPrimitive[sig] then
			return false
		end
		if sig == 'java.lang.String' then
			return true
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

			local toClassObj = self:import(sig)

			local jobject = arg
			-- how to determine if it is a class or not
			local envptr = self._ptr

			-- if its class is a java.lang.Class then use it for assignability test
			-- otherwise use its class for assignability test
			local jclass = self:_getObjectClass(jobject)
			local result
			if jclass == self._java_lang_Class._ptr then
				result = 0 ~= self:_isAssignableFrom(jobject, toClassObj._ptr)
			else
				result = 0 ~= self:_isAssignableFrom(jclass, toClassObj._ptr)
			end
			self:_deleteLocalRef(jclass)

			return result
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

--[[
converts from a Lua or Lua-wrapping-Java object to something that the JNI API can accept as an argument
--]]
function JNIEnv:_luaToJavaArg(arg, sig)
	local t = type(arg)
--DEBUG:print('JNIEnv:_luaToJavaArg', t, 'convert to', sig)
	if t == 'boolean'  then
		if sig == 'boolean' then
			return jboolean(arg)
		else
			error("can't cast boolean to "..sig)
		end
	elseif t == 'table' then
--DEBUG:print('arg is table, sig is', sig)
		if sig then
			if arg._classpath == sig then
				return assert(arg._ptr)
			end

			-- TODO who is calling this without sig anyways?
-- ALSO TODO
-- if a function has a signature of a prim and of Object
-- and you pass it a boxed prim
-- which will resolve?
-- in fact, Object does resolve
-- so so far so good
			local info = infoForPrims[sig]
			if info then
				if JavaObject:isa(arg) then
					local unboxedArgType = getUnboxedPrimitiveForClasspath[arg._classpath]
					if unboxedArgType then
						local getValueField = assert.index(getUnboxedValueGetterMethod, arg._classpath)
						local value = arg[getValueField](arg)
--DEBUG:print('unboxing from', arg, 'to', value)
						return info.ctype(value)
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
		return assert(arg._ptr)
	elseif t == 'string' then
		if isPrimitive[sig] then
			error("can't cast string to primitive")
		end
		if sig == 'java.lang.String' then
			return self:_str(arg)._ptr
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
--DEBUG:print('got number', arg)
--DEBUG:print('want', sig)
		local primInfo = infoForPrims[sig]
		if primInfo then
--DEBUG:print('is prim, returning', primInfo.ctype)
			return ffi.new(primInfo.ctype, arg)
		end
		-- if it's a boxed type then return it
		local unboxedSig = getUnboxedPrimitiveForClasspath[sig]
		if unboxedSig then
--DEBUG:print('is boxed, returning', sig)
			local toClassObj = self:import(sig)
--DEBUG:print('got class', toClassObj._classpath)
			local obj = toClassObj(arg)
--DEBUG:print('_luaToJavaArg result', obj._ptr, obj._classpath, 'for', sig)
			return obj._ptr
		end
		error("can't convert number to "..sig)
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

function JNIEnv:_javaToLuaArg(value, sig)
	if sig == 'void' then return end
	if sig == 'boolean' then
		if type(value) == 'table'
		and JavaObject:isa(value)
		and value._classpath == 'java.lang.Boolean'
		then
			return value:booleanValue()
		end
		return value ~= 0
	end
--DEBUG:print('here with sig', sig, 'and value', type(value), value)
	if isPrimitive[sig] then
--DEBUG:print('is prim')
		if type(value) == 'table'
		and JavaObject:isa(value)
		then
--DEBUG:print('here with value', value._classpath)
			local getValueField = getUnboxedValueGetterMethod[value._classpath]
			if getValueField then
				-- if we were going lua->java then I'd cast to the jni ctype here too...
				return value[getValueField](value)
			-- otherwise what?
			end
		end
		return value
	end

	-- if Java returned null then return Lua nil
	-- ... if the JNI is returning null object results as NULL pointers ...
	-- ... and the JNI itself segfaults when it gets passed a NULl that it doesn't like ...
	-- ... where else do I have to bulletproof calls to the JNI?
	if value == nil then return nil end

	-- convert / wrap the result
	return JavaObject._createObjectForClassPath{
		env = self,
		ptr = value,
		classpath = sig,
	}
end

function JNIEnv:_javaToLuaArgs(sigIndex, sig, ...)
	if select('#', ...) == 0 then return end
	return self:_javaToLuaArg(..., sig[sigIndex]),
		self:_javaToLuaArgs(sigIndex+1, sig, select(2, ...))
end

-- _loadClass points to JavaASMClass = require 'java.asmclass' or JavaASMDex = require 'java.asmdex'
--[[
'asm' can be a JavaASMClass/JavaASMDex, or a Lua string of bytecode (returned with :compile() above)
'newClassName' = classname, not necessary if using a JavaASMClass/JavaASMDex object.
--]]
function JNIEnv:_loadClass(asm, newClassName)
	local code
	if type(asm) == 'string' then
		code = asm
	elseif type(asm) == 'table' then
		--if JavaASMClass:isa(asm) or JavaASMDex:isa(asm) then
--DEBUG:print('asm class:')
--DEBUG:print(require 'ext.tolua'(asm))
		code = asm:compile()
--DEBUG:print('asm class code')
--DEBUG:print(require 'ext.string'.hexdump(code))
		newClassName = newClassName or asm.thisClass
	else
		error('JNIEnv:_loadClass() accepts JavaASMClass/JavaASMDex objects or Lua strings')
	end

	if self._usingAndroidJNI then
		local loader = self.Thread:currentThread():getContextClassLoader()

		local byteCodeArray = self:_newArray('byte', #code)
		do
			local ptr = byteCodeArray:_map()
			ffi.copy(ptr, code, #code)
			byteCodeArray:_unmap(ptr)
		end

		local ByteBuffer = self.java.nio.ByteBuffer
		assert(ByteBuffer._classpath, "failed to find java.nio.ByteBuffer")
		local byteBuf = ByteBuffer:wrap(byteCodeArray)

		local InMemoryDexClassLoader = self.dalvik.system.InMemoryDexClassLoader
		assert(InMemoryDexClassLoader._classpath, "failed to find dalvik.system.InMemoryDexClassLoader")
		local dexLoader = InMemoryDexClassLoader(byteBuf, loader)
		local clobj = dexLoader:loadClass(newClassName)
		if not clobj then
			error("JNI DefineClass failed to load "..tostring(newClassName))
		end
		return self:_fromJClass(clobj._ptr)
	else
		local newClassNameSlashSep = toSlashSepName(newClassName)

		local loader = self.Thread:currentThread():getContextClassLoader()
		self:_checkExceptions()
		local jclass = self:_defineClass(
			newClassNameSlashSep,
			loader._ptr,
			code,
			#code)
		self:_checkExceptions()
		-- is DefineClass supposed to throw an exception on failure?
		-- cuz on Android it's not...
		if jclass == nil then
			error("JNI DefineClass failed to load "..tostring(newClassName))
		end
		local cl = self:_fromJClass(jclass)
		self:_deleteLocalRef(jclass)
		return cl
	end
end

function JNIEnv:__tostring()
	return self.__name..'('..tostring(self._ptr)..')'
end

JNIEnv.__concat = string.concat


local Name

function JNIEnv:__index(k)
	-- automatic, right?
	--local v = rawget(self, k)
	--if v ~= nil then return v end
	-- however TODO
	-- JNIEnv still retains its .isa and .isaSet for the sake of ext.class isa inheritence test
	-- so explicitly skip those two in JNIEnv
	if k ~= 'isa' and k ~= 'isaSet' then
		local v = JNIEnv[k]
		if v ~= nil then return v end
	end

	if type(k) ~= 'string' then return end

	--[[ write protect and only allow _ lua vars
	-- don't build namespaces off private vars
	if k:match'^_' then
		print('JNIEnv.__index', k, "I am reserving underscores for private variables.  You were about to invoke a name resolve")
		print(debug.traceback())
		return
	end
	--]]

	-- alright this is anything not in self and not in the class
	-- do automatic namespace lookup here
	-- symbol resolution of global scope of 'k'
	-- I guess that means classes only

	-- ignore exceptions while we search for the class

	-- first search .

	self:_checkExceptions()
assert.eq(false, self._ignoringExceptions)
	self._ignoringExceptions = true
	local cl = self:import(k)
assert.eq(true, self._ignoringExceptions)
	self._ignoringExceptions = false
	self:_exceptionClear()
	if cl then return cl end

	-- next search java.lang.*
	self:_checkExceptions()
assert.eq(false, self._ignoringExceptions)
	self._ignoringExceptions = true
	local cl = self:import('java.lang.'..k)
assert.eq(true, self._ignoringExceptions)
	self._ignoringExceptions = false
	self:_exceptionClear()
	if cl then return cl end

--DEBUG:print('JNIEnv __index', k)
	return Name{env=self, name=k}
end


Name = class()
Name.__name = 'Name'
Name.subclass = nil

function Name:init(args)
	rawset(self, '_env', assert.index(args, 'env'))
	rawset(self, '_name', assert.index(args, 'name'))

	-- dont' allow writes
	setmetatable(self, table.union({}, Name, {
		__newindex = function(k,v)
			error("namespace object is write-protected")
		end,
	}))
end

function Name:__tostring()
	return 'Name('..rawget(self, '_name')..'.*'..')'
end

Name.__concat = string.concat

function Name:__index(k)
	-- avoid the last two fields I am leaving in Name for Lua OOP
	if k ~= 'isa' and k ~= 'isaSet' then
		local v = rawget(Name, k)
		if v ~= nil then return v end
	end

	--[[ write protect and only allow _ lua vars
	-- don't build namespaces off private vars
	-- this is really here to prevent stackoverflows during __index operations
	if k:match'^_' then
		print('Name.__index', k, "I am reserving underscores for private variables.  You were about to invoke a name resolve")
		print(debug.traceback())
		return
	end
	--]]

	local env = rawget(self, '_env')
	local classpath = rawget(self, '_name')..'.'..k

	-- ignore exceptions while we search for the class
	env:_checkExceptions()
assert.eq(false, env._ignoringExceptions)
	env._ignoringExceptions = true
	local cl = env:import(classpath)
assert.eq(true, env._ignoringExceptions)
	env._ignoringExceptions = false
	env:_exceptionClear()

	if cl then return cl end

--DEBUG:print('Name __index', k, 'classpath', classpath)
	return Name{env=env, name=classpath}
end


---------------- JNIEnv WRAPPER ----------------
-- just to save on one extra arg passing every single time...
-- do this last and make sure I'm not overwriting any method I just defined...

for f in ([[
GetVersion
DefineClass
FindClass
FromReflectedMethod
FromReflectedField
ToReflectedMethod
GetSuperclass
IsAssignableFrom
ToReflectedField
Throw
ThrowNew
ExceptionOccurred
ExceptionDescribe
ExceptionClear
FatalError
PushLocalFrame
PopLocalFrame
NewGlobalRef
DeleteGlobalRef
DeleteLocalRef
IsSameObject
NewLocalRef
EnsureLocalCapacity
AllocObject
NewObject
NewObjectV
NewObjectA
GetObjectClass
IsInstanceOf
GetMethodID
CallObjectMethod
CallObjectMethodV
CallObjectMethodA
CallBooleanMethod
CallBooleanMethodV
CallBooleanMethodA
CallByteMethod
CallByteMethodV
CallByteMethodA
CallCharMethod
CallCharMethodV
CallCharMethodA
CallShortMethod
CallShortMethodV
CallShortMethodA
CallIntMethod
CallIntMethodV
CallIntMethodA
CallLongMethod
CallLongMethodV
CallLongMethodA
CallFloatMethod
CallFloatMethodV
CallFloatMethodA
CallDoubleMethod
CallDoubleMethodV
CallDoubleMethodA
CallVoidMethod
CallVoidMethodV
CallVoidMethodA
CallNonvirtualObjectMethod
CallNonvirtualObjectMethodV
CallNonvirtualObjectMethodA
CallNonvirtualBooleanMethod
CallNonvirtualBooleanMethodV
CallNonvirtualBooleanMethodA
CallNonvirtualByteMethod
CallNonvirtualByteMethodV
CallNonvirtualByteMethodA
CallNonvirtualCharMethod
CallNonvirtualCharMethodV
CallNonvirtualCharMethodA
CallNonvirtualShortMethod
CallNonvirtualShortMethodV
CallNonvirtualShortMethodA
CallNonvirtualIntMethod
CallNonvirtualIntMethodV
CallNonvirtualIntMethodA
CallNonvirtualLongMethod
CallNonvirtualLongMethodV
CallNonvirtualLongMethodA
CallNonvirtualFloatMethod
CallNonvirtualFloatMethodV
CallNonvirtualFloatMethodA
CallNonvirtualDoubleMethod
CallNonvirtualDoubleMethodV
CallNonvirtualDoubleMethodA
CallNonvirtualVoidMethod
CallNonvirtualVoidMethodV
CallNonvirtualVoidMethodA
GetFieldID
GetObjectField
GetBooleanField
GetByteField
GetCharField
GetShortField
GetIntField
GetLongField
GetFloatField
GetDoubleField
SetObjectField
SetBooleanField
SetByteField
SetCharField
SetShortField
SetIntField
SetLongField
SetFloatField
SetDoubleField
GetStaticMethodID
CallStaticObjectMethod
CallStaticObjectMethodV
CallStaticObjectMethodA
CallStaticBooleanMethod
CallStaticBooleanMethodV
CallStaticBooleanMethodA
CallStaticByteMethod
CallStaticByteMethodV
CallStaticByteMethodA
CallStaticCharMethod
CallStaticCharMethodV
CallStaticCharMethodA
CallStaticShortMethod
CallStaticShortMethodV
CallStaticShortMethodA
CallStaticIntMethod
CallStaticIntMethodV
CallStaticIntMethodA
CallStaticLongMethod
CallStaticLongMethodV
CallStaticLongMethodA
CallStaticFloatMethod
CallStaticFloatMethodV
CallStaticFloatMethodA
CallStaticDoubleMethod
CallStaticDoubleMethodV
CallStaticDoubleMethodA
CallStaticVoidMethod
CallStaticVoidMethodV
CallStaticVoidMethodA
GetStaticFieldID
GetStaticObjectField
GetStaticBooleanField
GetStaticByteField
GetStaticCharField
GetStaticShortField
GetStaticIntField
GetStaticLongField
GetStaticFloatField
GetStaticDoubleField
SetStaticObjectField
SetStaticBooleanField
SetStaticByteField
SetStaticCharField
SetStaticShortField
SetStaticIntField
SetStaticLongField
SetStaticFloatField
SetStaticDoubleField
NewString
GetStringLength
GetStringChars
ReleaseStringChars
NewStringUTF
GetStringUTFLength
GetStringUTFChars
ReleaseStringUTFChars
GetArrayLength
NewObjectArray
GetObjectArrayElement
SetObjectArrayElement
NewBooleanArray
NewByteArray
NewCharArray
NewShortArray
NewIntArray
NewLongArray
NewFloatArray
NewDoubleArray
GetBooleanArrayElements
GetByteArrayElements
GetCharArrayElements
GetShortArrayElements
GetIntArrayElements
GetLongArrayElements
GetFloatArrayElements
GetDoubleArrayElements
ReleaseBooleanArrayElements
ReleaseByteArrayElements
ReleaseCharArrayElements
ReleaseShortArrayElements
ReleaseIntArrayElements
ReleaseLongArrayElements
ReleaseFloatArrayElements
ReleaseDoubleArrayElements
GetBooleanArrayRegion
GetByteArrayRegion
GetCharArrayRegion
GetShortArrayRegion
GetIntArrayRegion
GetLongArrayRegion
GetFloatArrayRegion
GetDoubleArrayRegion
SetBooleanArrayRegion
SetByteArrayRegion
SetCharArrayRegion
SetShortArrayRegion
SetIntArrayRegion
SetLongArrayRegion
SetFloatArrayRegion
SetDoubleArrayRegion
RegisterNatives
UnregisterNatives
MonitorEnter
MonitorExit
GetJavaVM
GetStringRegion
GetStringUTFRegion
GetPrimitiveArrayCritical
ReleasePrimitiveArrayCritical
GetStringCritical
ReleaseStringCritical
NewWeakGlobalRef
DeleteWeakGlobalRef
ExceptionCheck
NewDirectByteBuffer
GetDirectBufferAddress
GetDirectBufferCapacity
GetObjectRefType
]]):gmatch'%S+' do
	local k = '_'..f:sub(1,1):lower()..f:sub(2)
	assert.eq(JNIEnv[k], nil, k)
	JNIEnv[k] = function(self, ...)
		local envptr = self._ptr
		return envptr[0][f](envptr, ...)
	end
end

return JNIEnv
