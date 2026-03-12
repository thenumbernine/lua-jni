--[[
This is a wrapper for a class / type in Java, i.e. a jclass in JNI
--]]
local assert = require 'ext.assert'
local class = require 'ext.class'
local string = require 'ext.string'
local table = require 'ext.table'
local tolua = require 'ext.tolua'
local JavaObject = require 'java.object'
local JavaMethod = require 'java.method'
local JavaField = require 'java.field'
local JavaCallResolve = require 'java.callresolve'
local getJNISig = require 'java.util'.getJNISig


-- is a Java class a Java object?
-- should JavaClass inherit from JavaObject?
local JavaClass = class(JavaObject)
JavaClass.__name = 'JavaClass'
JavaClass.super = nil
JavaClass.class = nil
JavaClass.subclass = nil
--JavaClass.isa = nil -- handled in __index
--JavaClass.isaSet = nil -- handled in __index

JavaClass._exists = true	-- versus JNI namespace search's_exists == false
function JavaClass:init(args)
	-- matches JavaObject, its superclass, but here I'm not calling JavaObject:init...
	local env = assert.index(args, 'env')
	self._env = env
	local envptr = env._ptr

	local ptr = assert.index(args, 'ptr')
	self._ptr = envptr[0].NewGlobalRef(envptr, ptr)

	self._classpath = assert.index(args, 'classpath')

	-- locking namespace for java name resolve,
	-- so define all to-be-used variables here,
	-- even as 'false' for the if-exists tests to fail:
	self._fields = false
	self._methods = false
	self._ctors = false

	-- TODO save ctors, methods, and fields separately?
	-- then no need to class-detect upon __index...

	-- modifiers
	-- TODO should the caller do this? like is done with reflection ... hmm
	-- caller is just JNIEnv:_findClass
	local envptr = self._env._ptr
	-- hmm, if I store java/lang/Class instead of retrieve it here every time then I get segafults
	-- why?  I even went out of my way to start NewGlobalRef'ing all my java classes & objects ....
	-- (fun fact, never NewGlobalRef'ing them never once caused a segfault, and now that I assumed it was I implemented it and the segfault turned out to be something else)
	local modifiersMethodID = envptr[0].GetMethodID(
		envptr,
		envptr[0].FindClass(envptr, 'java/lang/Class'),
		'getModifiers',
		'()I')
	local modifiers = envptr[0].CallIntMethod(
		envptr,
		self._ptr,
		modifiersMethodID)

--DEBUG:print('class', self._classpath, 'modifiers', modifiers)
	self._isPublic = 0 ~= bit.band(modifiers, 1)
	self._isPrivate = 0 ~= bit.band(modifiers, 2)
	self._isProtected = 0 ~= bit.band(modifiers, 4)
	self._isStatic = 0 ~= bit.band(modifiers, 8)
	self._isFinal = 0 ~= bit.band(modifiers, 16)
	self._isSuper = 0 ~= bit.band(modifiers, 32)	-- same as 'isSynchronized'
	self._isVolatile = 0 ~= bit.band(modifiers, 64)
	self._isTransient = 0 ~= bit.band(modifiers, 128)
	self._isNative = 0 ~= bit.band(modifiers, 256)
	self._isInterface = 0 ~= bit.band(modifiers, 512)
	self._isAbstract = 0 ~= bit.band(modifiers, 1024)
	self._isStrict = 0 ~= bit.band(modifiers, 2048)

	-- evaluate after _setupReflection
	-- set it 'false' if the class isn't SAM
	-- set it to the one abstract method if it is
	self._samMethod = false

	-- set our __newindex last after we're done writing to it
	local mt = getmetatable(self)
	setmetatable(self, table.union({}, mt, {
		__newindex = function(self, k, v)
			--see if we are trying to write to a Java field
			if type(k) == 'string'
			and not k:match'^_'
			then
				local fieldsForName = self._fields[k]
				if fieldsForName then
					local field = fieldsForName[1]
					assert(field._isStatic, "classes can't write to member fields")
					return field:_set(self, v)	-- call the setter of the field
				end

				local methodsForName = self._methods[k]
				if methodsForName then
					error("can't overwrite a Java method "..k)
				end
				error("JavaClass.__newindex("..tostring(k)..', '..tostring(v).."): object is write-protected -- can't write private members afer creation")
			end

			-- finally do our write
			rawset(self, k, v)
		end,
	}))
end

-- call this after creating JavaClass to fill its reflection contents
-- TODO this is using getFields and getMethods
-- should I use getDeclaredFields and getDeclaredMethods ?
--	yes, because that can get private ones as well, and then I can change their accessibility at runtime.
--  and also I can better calculate subclass distance for better calculating correct overload signature to use.
-- TODO use JNI invokes throughout here so I don't need to worry about my own Lua object cache / construction stuff going on
function JavaClass:_setupReflection()
	local env = self._env
	local envptr = env._ptr

	-- throw any excpetions occurred so far
	-- because from here on out in setupReflection I will be throwing exceptions away (java.lang.NoSuchMethodError, etc)
	env:_checkExceptions()
	local pushIgnore = env._ignoringExceptions
	env._ignoringExceptions = true

--DEBUG:print('calling setupReflect on', self._classpath)
	assert.eq(false, self._fields, "_setupReflection expected _fields to be false")
	assert.eq(false, self._methods, "_setupReflection expected _methods to be false")
	assert.eq(false, self._ctors, "_setupReflection expected _ctors to be false")
	self._fields = {}		-- self._fields[fieldname][index] = JavaField
	self._methods = {}		-- self._methods[fieldname][index] = JavaMethod
	self._ctors = table()	-- self._ctors[index] = JavaMethod

	local java_lang_Class = env._java_lang_Class
	local java_lang_reflect_Field = env._java_lang_reflect_Field
	local java_lang_reflect_Method = env._java_lang_reflect_Method
	local java_lang_reflect_Constructor = env._java_lang_reflect_Constructor

	local jobjectFields = envptr[0].CallObjectMethod(
		envptr,
		self._ptr,
		java_lang_Class._java_lang_Class_getFields._ptr)
	local numFields = envptr[0].GetArrayLength(envptr, jobjectFields)

	local jobjectMethods = envptr[0].CallObjectMethod(
		envptr,
		self._ptr,
		java_lang_Class._java_lang_Class_getMethods._ptr)
	local numMethods = envptr[0].GetArrayLength(envptr, jobjectMethods)

	-- manually handling memory during _setupReflection()
	local jobjectCtors = envptr[0].CallObjectMethod(
		envptr,
		self._ptr,
		java_lang_Class._java_lang_Class_getConstructors._ptr)
	local numCtors = envptr[0].GetArrayLength(envptr, jobjectCtors)

--DEBUG:print(self._classpath..' has '..numFields..' fields and '..numMethods..' methods and '..numCtors..' constructors')

	-- now convert the fields/methods into a key-based lua-table to integer-based lua-table for each name ...
	if jobjectFields == nil then
		io.stderr:write(' !!! DANGER !!! failed to get fields from class '..self._classpath..'\n')
	else
		for i=0,numFields-1 do
			-- Field
			local field = envptr[0].GetObjectArrayElement(
				envptr,
				jobjectFields,
				i)

			-- String
			local jstringName = envptr[0].CallObjectMethod(
				envptr,
				field,
				java_lang_reflect_Field._java_lang_reflect_Field_getName._ptr)
			local name = env:_fromJString(jstringName)
			env:_deleteLocalRef(jstringName)

			-- Class
			local fieldType = envptr[0].CallObjectMethod(
				envptr,
				field,
				java_lang_reflect_Field._java_lang_reflect_Field_getType._ptr)

			-- String
			local jstringFieldClassPath = envptr[0].CallObjectMethod(
				envptr,
				fieldType,
				java_lang_Class._java_lang_Class_getTypeName._ptr)
			env:_deleteLocalRef(fieldType)
			
			local fieldClassPath = env:_fromJString(jstringFieldClassPath)
			env:_deleteLocalRef(jstringFieldClassPath)
--DEBUG:print('fieldType', fieldClassPath)

			local modifiers = envptr[0].CallIntMethod(
				envptr,
				field,
				java_lang_reflect_Field._java_lang_reflect_Field_getModifiers._ptr)
--DEBUG:print('modifiers', modifiers)

			-- ok now switch this reflect field obj to a jni jfieldID
			local jfieldID = envptr[0].FromReflectedField(
				envptr,
				field)
			env:_deleteLocalRef(field)

--DEBUG:print('jfieldID', jfieldID)
			assert(jfieldID ~= nil, "couldn't get jfieldID from reflect field for "..tostring(name))

			local fieldObj = JavaField{
				env = env,
				ptr = jfieldID,
				sig = fieldClassPath,
				name = name,
				-- or just pass the modifiers?
				isPublic = 0 ~= bit.band(modifiers, 1),
				isPrivate = 0 ~= bit.band(modifiers, 2),
				isProtected = 0 ~= bit.band(modifiers, 4),
				isStatic = 0 ~= bit.band(modifiers, 8),
				isFinal = 0 ~= bit.band(modifiers, 0x10),
				isVolatile = 0 ~= bit.band(modifiers, 0x40),
				isTransient = 0 ~= bit.band(modifiers, 0x80),
				isSynthetic = 0 ~= bit.band(modifiers, 0x1000),
				isEnum = 0 ~= bit.band(modifiers, 0x4000),
			}
			-- TODO delete 
			-- ... but JavaField doesn't duplicate jfieldID to a GlobalRef, 
			-- ... so that would force java.field to segfault upon use ...
			-- so TODO change java.field and java.method to *NOT STORE jfieldID/jmethodID's

			self._fields[name] = self._fields[name] or table()
			self._fields[name]:insert(fieldObj)
--DEBUG:print('field['..i..'] = '..name, fieldClassPath)
		end
		env:_deleteLocalRef(jobjectFields)
	end

	-- TODO how does name resolution go? fields or methods first?
	-- I think they shouldn't ever overlap?
	if jobjectMethods == nil then
		io.stderr:write(' !!! DANGER !!! failed to get methods from class '..self._classpath..'\n')
	else
		for i=0,numMethods-1 do
			-- Method
			local method = envptr[0].GetObjectArrayElement(
				envptr,
				jobjectMethods,
				i)

			-- String
			local jstringName = envptr[0].CallObjectMethod(
				envptr,
				method,
				java_lang_reflect_Method._java_lang_reflect_Method_getName._ptr)
			local name = env:_fromJString(jstringName)
			env:_deleteLocalRef(jstringName)

			local sig = table()

			-- Class
			local methodReturnType = envptr[0].CallObjectMethod(
				envptr,
				method,
				java_lang_reflect_Method._java_lang_reflect_Method_getReturnType._ptr)
			
			-- String
			local jstringReturnTypeClassPath = envptr[0].CallObjectMethod(
				envptr,
				methodReturnType,
				java_lang_Class._java_lang_Class_getTypeName._ptr)
			env:_deleteLocalRef(methodReturnType)

			local returnTypeClassPath = env:_fromJString(jstringReturnTypeClassPath)
			env:_deleteLocalRef(jstringReturnTypeClassPath)

			sig:insert(returnTypeClassPath)

			-- Class[]
			local paramTypes = envptr[0].CallObjectMethod(
				envptr,
				method,
				java_lang_reflect_Method._java_lang_reflect_Method_getParameterTypes._ptr)
			local numParamTypes = envptr[0].GetArrayLength(envptr, paramTypes)

			for j=0,numParamTypes-1 do
				-- Class
				local methodParamType = envptr[0].GetObjectArrayElement(envptr, paramTypes, j)

				-- String
				local paramClassPath = envptr[0].CallObjectMethod(
					envptr,
					methodParamType,
					java_lang_Class._java_lang_Class_getTypeName._ptr)
				env:_deleteLocalRef(methodParamType)
				
				sig:insert(env:_fromJString(paramClassPath))
				
				env:_deleteLocalRef(paramClassPath)
			end
			env:_deleteLocalRef(paramTypes)

			-- int
			local modifiers = envptr[0].CallIntMethod(
				envptr,
				method,
				java_lang_reflect_Method._java_lang_reflect_Method_getModifiers._ptr)

			local jmethodID = envptr[0].FromReflectedMethod(
				envptr,
				method)
			env:_deleteLocalRef(method)

--DEBUG:print('jmethodID', jmethodID)
			assert(jmethodID ~= nil, "couldn't get jmethodID from reflect method for "..tostring(name))

			local methodObj = JavaMethod{
				env = env,
				ptr = jmethodID,
				name = name,
				sig = sig,
				-- or just pass the modifiers?
				isPublic = 0 ~= bit.band(modifiers, 1),
				isPrivate = 0 ~= bit.band(modifiers, 2),
				isProtected = 0 ~= bit.band(modifiers, 4),
				isStatic = 0 ~= bit.band(modifiers, 8),
				isFinal = 0 ~= bit.band(modifiers, 0x10),
				isSynchronized = 0 ~= bit.band(modifiers, 0x20),
				isBridge = 0 ~= bit.band(modifiers, 0x40),
				isVarArgs = 0 ~= bit.band(modifiers, 0x80),
				isNative = 0 ~= bit.band(modifiers, 0x100),
				isAbstract = 0 ~= bit.band(modifiers, 0x400),
				isStrict = 0 ~= bit.band(modifiers, 0x800),
				isSynthetic = 0 ~= bit.band(modifiers, 0x1000),
			}

			self._methods[name] = self._methods[name] or table()
			self._methods[name]:insert(methodObj)
--DEBUG:print('method['..i..'] = '..name, tolua(sig))
		end
		env:_deleteLocalRef(jobjectMethods)
	end

	-- can constructors use JNIEnv.FromReflectedMethod ?
	if jobjectCtors == nil then
		io.stderr:write(' !!! DANGER !!! failed to get constructors from class '..self._classpath..'\n')
	else
		local ctorname = '<init>'	-- all constructors have the same name
		local foundDefaultCtor
		for i=0,numCtors-1 do
			-- Constructor
			local method = envptr[0].GetObjectArrayElement(envptr, jobjectCtors, i)

			local sig = table()
			sig:insert'void'	-- constructor signature has void return type

			-- Class[]
			local paramTypes = envptr[0].CallObjectMethod(
				envptr,
				method,
				java_lang_reflect_Constructor._java_lang_reflect_Constructor_getParameterTypes._ptr)
			local numParamTypes = envptr[0].GetArrayLength(envptr, paramTypes)

			for j=0,numParamTypes-1 do
				local methodParamType = envptr[0].GetObjectArrayElement(envptr, paramTypes, j)

				-- String
				local paramClassPath = envptr[0].CallObjectMethod(
					envptr,
					methodParamType,
					java_lang_Class._java_lang_Class_getTypeName._ptr)

				env:_deleteLocalRef(methodParamType)

				sig:insert(env:_fromJString(paramClassPath))

				env:_deleteLocalRef(paramClassPath)
			end
			env:_deleteLocalRef(paramTypes)

			-- int
			local modifiers = envptr[0].CallIntMethod(
				envptr,
				method,
				java_lang_reflect_Constructor._java_lang_reflect_Constructor_getModifiers._ptr)
--DEBUG:print('modifiers', modifiers)

			local jmethodID = envptr[0].FromReflectedMethod(envptr, method)
			env:_deleteLocalRef(method)
--DEBUG:print('jmethodID', jmethodID)

			assert(jmethodID ~= nil, "couldn't get jmethodID from reflect constructor")

			if #sig == 1 and sig[1] == 'void' then
				foundDefaultCtor = true
			end

			local methodObj = JavaMethod{
				env = env,
				ptr = jmethodID,
				name = ctorname,
				sig = sig,
				-- or just pass the modifiers?
				isPublic = 0 ~= bit.band(modifiers, 1),
				isPrivate = 0 ~= bit.band(modifiers, 2),
				isProtected = 0 ~= bit.band(modifiers, 4),
				isStatic = 0 ~= bit.band(modifiers, 8),
				isFinal = 0 ~= bit.band(modifiers, 0x10),
				isSynchronized = 0 ~= bit.band(modifiers, 0x20),
				isBridge = 0 ~= bit.band(modifiers, 0x40),
				isVarArgs = 0 ~= bit.band(modifiers, 0x80),
				isNative = 0 ~= bit.band(modifiers, 0x100),
				isAbstract = 0 ~= bit.band(modifiers, 0x400),
				isStrict = 0 ~= bit.band(modifiers, 0x800),
				isSynthetic = 0 ~= bit.band(modifiers, 0x1000),
			}

			self._ctors:insert(methodObj)
--DEBUG:print('constructor['..i..'] = '..tolua(sig))
		end

		-- another Java quirk: every function has a default no-arg constructor
		-- but it won't be listed in the java.lang.Class.getConstructors() list
		--  unless it was explicitly defined
		if not foundDefaultCtor then
--DEBUG:print('getting default ctor of class', self._classpath)
			-- sometimes the default isn't there, like in java.lang.Class ...
			local defaultCtorMethod = self:_method{
				name = ctorname,
				sig = {},
			}

			-- can this ever not exist?
			-- maybe by protecting it or something?
			if defaultCtorMethod then
				self._ctors:insert(defaultCtorMethod)
			end
		end
		env:_deleteLocalRef(jobjectCtors)
	end


	-- determine if this is a SAM class or not
	-- Java says don't SAM abstract-classes.  but then there is all of Swing and JavaFX ...
	--if self._isInterface then
	for name,options in pairs(self._methods) do
		for _,option in ipairs(options) do
			-- see if the first method we find is abstract...
			if not self._samMethod then
				if not option._isAbstract then
					-- it wasn't abstract, fail
					goto detectSAMDone
				end
				-- write our sam method and see if there are more...
				self._samMethod = option
			else
				-- there were more methods, this isn't SAM, clear it and fail
				self._samMethod = false
				goto detectSAMDone
			end
		end
	end
::detectSAMDone::

	env._ignoringExceptions = pushIgnore
	env:_exceptionClear()
end

-- equivalent of .class
-- converts this from a JavaClass to a java.lang.Class JavaObject
-- TODO - can I just make JavaClass a subclass of JavaObject?
-- but if I did, what would I do about JavaObject:_getClass() returning the JavaClass of an object, versus this?
function JavaClass:_class()
	local JavaObject = require 'java.object'

	-- BIG NOTICE
	-- this will produce multiple distinct "java.lang.Class" JavaClass's
	--  which, apart from this method, courtesy of the jniEnv._classesLoaded[] cache,
	--  there is no other way in the API to do
	--  (besides instanciating your own JavaClass{} around your own jclass ptr
	return JavaObject{
		env = self._env,
		ptr = self._ptr,
		classpath = 'java.lang.Class',
	}
end

--[[
args:
	name
	sig
		= table of args as dot-separated classpaths or primitive names,
		first arg is return type
	isStatic = boolean
	... the rest are forwarded to JavaMethod
--]]
function JavaClass:_method(args)
	assert.type(args, 'table')

	local env = self._env
	env:_checkExceptions()

	local funcname = assert.type(assert.index(args, 'name'), 'string')
	local isStatic = args.isStatic
	local sig = assert.type(assert.index(args, 'sig'), 'table')
	local sigstr = getJNISig(sig)
--DEBUG:print('sigstr', sigstr)

	local jmethodID
	if isStatic then
		jmethodID = env._ptr[0].GetStaticMethodID(env._ptr, self._ptr, funcname, sigstr)
	else
		jmethodID = env._ptr[0].GetMethodID(env._ptr, self._ptr, funcname, sigstr)
	end
	-- will this throw an exception? probably.
	if jmethodID == nil then
		local ex = env:_exceptionOccurred()
		return
			nil,
			"failed to find method "..tostring(funcname)
				..(isStatic and ' static' or '')
				..' '..tolua(sigstr),
			ex
	end

	args.env = env
	args.class = self
	args.ptr = jmethodID
	return JavaMethod(args)
end

--[[
args:
	name
	sig = table of args as dot-separated classpaths or primitive names,
	isStatic = boolean
	... the rest are forwarded to JavaField
--]]
function JavaClass:_field(args)
	assert.type(args, 'table')

	local env = self._env
	env:_checkExceptions()

	local fieldname = assert.type(assert.index(args, 'name'), 'string')
	local sig = assert.type(assert.index(args, 'sig'), 'string')
	local sigstr = getJNISig(sig)
	local isStatic = args.isStatic
	local jfieldID
	if isStatic then
		jfieldID = env._ptr[0].GetStaticFieldID(env._ptr, self._ptr, fieldname, sigstr)
	else
		jfieldID = env._ptr[0].GetFieldID(env._ptr, self._ptr, fieldname, sigstr)
	end
	if jfieldID == nil then
		local ex = env:_exceptionOccurred()
		return nil, "failed to find jfieldID="..tostring(fieldname)..' sig='..tostring(sig)..(isStatic and ' static' or ''), ex
	end

	args.env = env
	args.ptr = jfieldID
	return JavaField(args)
end

function JavaClass:_new(...)
	-- shorthand for building a class from a Java-lambda equivalent Lua-function
	if type((...)) == 'function' then
		return self:_cb(...)
	end

	local ctors = self._ctors
	if not ctors or #ctors == 0 then
		error("can't new, no constructors present for "..self._classpath)
	else
		-- TODO here and JavaCallResolve, we are translating args multiple times
		-- TODO just do it once
		local ctor = JavaCallResolve.resolve('<init>', ctors, self, ...)
		if not ctor then
			error("couldn't match args to any ctors of "..self._classpath..":\n"
				..'\t'..ctors:mapi(function(x) return tolua(x._sig) end)
					:concat'\n\t'..'\n'
				..'args:\n'
				..'\t'..table{...}:mapi(function(x) return tolua(x) end)
					:concat'\n\t'
			)
		end
		return ctor:_new(self, ...)
	end
end

function JavaClass:__call(...)
	return self:_new(...)
end

function JavaClass:_super()
	local env = self._env
	local jsuper = env._ptr[0].GetSuperclass(env._ptr, self._ptr)
	return env:_fromJClass(jsuper)
end

-- idk that theres an equivalent operator in java?
-- does instanceof of an object of the class
function JavaClass:_isAssignableFrom(classTo)
	local env = self._env
	if type(classTo) == 'string' then
		local classpath = classTo
		classTo = env:_findClass(classpath)
		if classTo == nil then
			error("tried to cast to an unknown class "..classpath)
		end
	elseif type(classTo) == 'cdata' then
		classTo = env:_fromJClass(classTo)
	elseif type(classTo) == 'table' then
		-- TODO assert it's a JavaClass?
		-- TODO if it's a JavaObject then get its :_getClass() ?
	else
		error("can't cast to non-class "..tostring(classTo))
	end
	local canCast = env._ptr[0].IsAssignableFrom(
		env._ptr,
		self._ptr,
		classTo._ptr
	)
	return canCast ~= 0, classTo
end

-- calls in java `class.getTypeName()`
function JavaClass:_name()
	local classObj = self._env._java_lang_Class
	local classpath = classObj._java_lang_Class_getTypeName(self)
	if classpath == nil then return nil end
	return tostring(classpath)
end

function JavaClass:_throwNew()
	self._env:_throwNew(self)
end

function JavaClass:__index(k)

	-- if self[k] exists then this isn't called
	if k ~= 'isa' and k ~= 'isaSet' then
		local cl = getmetatable(self)
		local v = cl[k]
		if v ~= nil then return v end
	end

	if type(k) ~= 'string' then return end

	if k == 'class' then
		return self:_class()
	end

	-- don't build namespaces off private vars
	if k:match'^_' then
		print('JavaClass.__index', k, "I am reserving underscores for private variables.  You were about to invoke a name resolve")
		print(debug.traceback())
		return
	end

	-- now check fields/methods
--DEBUG:print('here', self._classpath)
--DEBUG:print(require'ext.table'.keys(self._fields):sort():concat', ')
	local fieldsForName = self._fields[k]
	if fieldsForName then
		-- assert it is a static field?
		local field = fieldsForName[1]
		return field:_get(self)	-- call the getter of the field
	end

--DEBUG:print(require'ext.table'.keys(self._methods):sort():concat', ')
	local methodsForName = self._methods[k]
	if methodsForName then
--DEBUG:print('#methodsForName', k, #methodsForName)
		-- now our choice of methodsForName[] will depend on the calling args...
		return JavaCallResolve{
			name = k,
			caller = self,
			options = methodsForName,
		}
	end

	-- check inner-classes?
	local env = rawget(self, '_env')
	local classpath = self._classpath..'$'..k
	env:_checkExceptions()
assert.eq(false, env._ignoringExceptions)
	env._ignoringExceptions = true
	local cl = env:_findClass(classpath)
assert.eq(true, env._ignoringExceptions)
	env._ignoringExceptions = false
	env:_exceptionClear()
	if cl then return cl end
end

--[[
build the subclass used for _cb()
- func = callback
- safe = whether invoking this function should use a new lite-thread and new lua state or not.
--]]
function JavaClass:_cbClass(func, safe)
	local env = self._env

	local samMethod = self._samMethod

	local parentClass, interfaces
	if self._isInterface then
		parentClass = 'java.lang.Object'
		interfaces = {self._classpath}
	else
		parentClass = self._classpath
	end

	local JavaLuaClass = require 'java.luaclass'
	local cl = JavaLuaClass{
		env = env,
		extends = parentClass,
		implements = interfaces,
		methods = {
			{
				name = samMethod._name,
				sig = samMethod._sig,
				value = func,
				newLuaState = safe,
			},
		},
	}

	return cl
end

-- build a subclass of "single-abstract-method" class for a Java-lamdba-equivalent for a Lua-function
function JavaClass:_cb(func, ...)
	return self:_cbClass(func)(...)
end

-- if this calls parent class __tostring, that will call JavaObject:__tostring(), which calls the Java .toString(), but it will be on a jclass pointer...
-- ... which OpenJDK doesn't mind, but Android will segfault because Google is retarded.
-- Google Gemini tells me Android JNI segfaults so much and has so many exceptional cases to their API because "it makes it go faster".  Like speed holes I guess.
function JavaClass:__tostring()
	return self:_getDebugStr()
end

return JavaClass
