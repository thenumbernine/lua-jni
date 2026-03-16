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

function JavaClass:init(args)
	-- matches JavaObject, its superclass, but here I'm not calling JavaObject:init...
	local env = assert.index(args, 'env')
	self._env = env

	local ptr = assert.index(args, 'ptr')
	self._ptr = env:_newGlobalRef(ptr)

	self._classpath = assert.index(args, 'classpath')

	self.super = false

	-- locking namespace for java name resolve,
	-- so define all to-be-used variables here,
	-- even as 'false' for the if-exists tests to fail:
	self._fields = {}		-- self._fields[fieldname][index] = JavaField
	self._methods = {}		-- self._methods[fieldname][index] = JavaMethod
	--self._childClasses = {}	-- self._childClasses[classname] = JavaClass
	self._interfaces = table()

	-- TODO save ctors, methods, and fields separately?
	-- then no need to class-detect upon __index...

	-- modifiers
	-- TODO should the caller do this? like is done with reflection ... hmm
	-- caller is just JNIEnv:import
	-- hmm, if I store java/lang/Class instead of retrieve it here every time then I get segafults
	-- why?  I even went out of my way to start NewGlobalRef'ing all my java classes & objects ....
	-- (fun fact, never NewGlobalRef'ing them never once caused a segfault, and now that I assumed it was I implemented it and the segfault turned out to be something else)
	local modifiersMethodID = env:_getMethodID(
		env:_findClass'java/lang/Class',
		'getModifiers',
		'()I')
	local modifiers = env:_callIntMethod(
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
			--[[ write protect and only allow _ lua vars
			and not k:match'^_'
			--]]
			then
				local fieldsForName = rawget(self, '_fields')[k]
				if fieldsForName then
					local field = fieldsForName[1]
					assert(field._isStatic, "classes can't write to member fields")
					return field:_set(self, v)	-- call the setter of the field
				end

				--[[ meh?
				local methodsForName = self._methods[k]
				if methodsForName then
					error("can't overwrite a Java method "..k)
				end
				--]]
				--[[ write protect and only allow _ lua vars
				error("JavaClass.__newindex("..tostring(k)..', '..tostring(v).."): object is write-protected -- can't write private members afer creation")
				--]]
			end

			-- finally do our write
			rawset(self, k, v)
		end,
	}))
end

-- call this after creating JavaClass to fill its reflection contents
function JavaClass:_setupReflection()
	local env = self._env

	-- throw any excpetions occurred so far
	-- because from here on out in setupReflection I will be throwing exceptions away (java.lang.NoSuchMethodError, etc)
	env:_checkExceptions()
	local pushIgnore = env._ignoringExceptions
	env._ignoringExceptions = true

--DEBUG:print('calling setupReflect on', self._classpath)

	local _ctors = table()	-- _ctors[index] = JavaMethod
	self._methods['<init>'] = _ctors

	local java_lang_Class = env._java_lang_Class
	local java_lang_reflect_Field = env._java_lang_reflect_Field
	local java_lang_reflect_Method = env._java_lang_reflect_Method
	local java_lang_reflect_Constructor = env._java_lang_reflect_Constructor

	-- now convert the fields/methods into a key-based lua-table to integer-based lua-table for each name ...
	local jobjectFields = env:_callObjectMethod(self._ptr, java_lang_Class._java_lang_Class_getDeclaredFields._ptr)
	if jobjectFields == nil then
		io.stderr:write(' !!! DANGER !!! failed to get fields from class '..self._classpath..'\n')
	else
		local numFields = env:_getArrayLength(jobjectFields)
--DEBUG:print('...# fields', numFields)
		for i=0,numFields-1 do
			-- Field
			local field = env:_getObjectArrayElement(jobjectFields, i)

			-- String
			local jstringName = env:_callObjectMethod(field, java_lang_reflect_Field._java_lang_reflect_Field_getName._ptr)
			local name = env:_fromJString(jstringName)
			env:_deleteLocalRef(jstringName)

--DEBUG:print('...field['..i..']='..require 'ext.tolua'(name))

			-- Class
			local fieldType = env:_callObjectMethod(field, java_lang_reflect_Field._java_lang_reflect_Field_getType._ptr)

			-- String
			local jstringFieldClassPath = env:_callObjectMethod(fieldType, java_lang_Class._java_lang_Class_getTypeName._ptr)
			env:_deleteLocalRef(fieldType)

			local fieldClassPath = env:_fromJString(jstringFieldClassPath)
			env:_deleteLocalRef(jstringFieldClassPath)
--DEBUG:print('fieldType', fieldClassPath)

			local modifiers = env:_callIntMethod(field, java_lang_reflect_Field._java_lang_reflect_Field_getModifiers._ptr)
--DEBUG:print('modifiers', modifiers)

			-- ok now switch this reflect field obj to a jni jfieldID
			local jfieldID = env:_fromReflectedField(field)
			env:_deleteLocalRef(field)

--DEBUG:print('jfieldID', jfieldID)
			assert(jfieldID ~= nil, "couldn't get jfieldID from reflect field for "..tostring(name))

			local fieldObj = JavaField{
				env = env,
				ptr = jfieldID,
				sig = fieldClassPath,
				name = name,
				class = self._classpath,
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
	local jobjectMethods = env:_callObjectMethod(self._ptr, java_lang_Class._java_lang_Class_getDeclaredMethods._ptr)
	if jobjectMethods == nil then
		io.stderr:write(' !!! DANGER !!! failed to get methods from class '..self._classpath..'\n')
	else
		local numMethods = env:_getArrayLength(jobjectMethods)
		for i=0,numMethods-1 do
			-- Method
			local method = env:_getObjectArrayElement(jobjectMethods, i)

			-- String
			local jstringName = env:_callObjectMethod(method, java_lang_reflect_Method._java_lang_reflect_Method_getName._ptr)
			local name = env:_fromJString(jstringName)
			env:_deleteLocalRef(jstringName)

--DEBUG:print('...got method', name)

			local sig = table()

			-- Class
			local methodReturnType = env:_callObjectMethod(method, java_lang_reflect_Method._java_lang_reflect_Method_getReturnType._ptr)

			-- String
			local jstringReturnTypeClassPath = env:_callObjectMethod(methodReturnType, java_lang_Class._java_lang_Class_getTypeName._ptr)
			env:_deleteLocalRef(methodReturnType)

			local returnTypeClassPath = env:_fromJString(jstringReturnTypeClassPath)
			env:_deleteLocalRef(jstringReturnTypeClassPath)

			sig:insert(returnTypeClassPath)

			-- Class[]
			local paramTypes = env:_callObjectMethod(method, java_lang_reflect_Method._java_lang_reflect_Method_getParameterTypes._ptr)
			local numParamTypes = env:_getArrayLength(paramTypes)

			for j=0,numParamTypes-1 do
				-- Class
				local methodParamType = env:_getObjectArrayElement(paramTypes, j)

				-- String
				local paramClassPath = env:_callObjectMethod(methodParamType, java_lang_Class._java_lang_Class_getTypeName._ptr)
				env:_deleteLocalRef(methodParamType)

				sig:insert(env:_fromJString(paramClassPath))

				env:_deleteLocalRef(paramClassPath)
			end
			env:_deleteLocalRef(paramTypes)

			-- int
			local modifiers = env:_callIntMethod(method, java_lang_reflect_Method._java_lang_reflect_Method_getModifiers._ptr)

			local jmethodID = env:_fromReflectedMethod(method)
			env:_deleteLocalRef(method)

--DEBUG:print('jmethodID', jmethodID)
			assert(jmethodID ~= nil, "couldn't get jmethodID from reflect method for "..tostring(name))

			local methodObj = JavaMethod{
				env = env,
				ptr = jmethodID,
				name = name,
				class = self._classpath,
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
	local jobjectCtors = env:_callObjectMethod(self._ptr, java_lang_Class._java_lang_Class_getDeclaredConstructors._ptr)
	if jobjectCtors == nil then
		io.stderr:write(' !!! DANGER !!! failed to get constructors from class '..self._classpath..'\n')
	else
		local ctorname = '<init>'	-- all constructors have the same name
		local foundDefaultCtor
		local numCtors = env:_getArrayLength(jobjectCtors)
		for i=0,numCtors-1 do
			-- Constructor
			local method = env:_getObjectArrayElement(jobjectCtors, i)

			local sig = table()
			sig:insert'void'	-- constructor signature has void return type

			-- Class[]
			local paramTypes = env:_callObjectMethod(method, java_lang_reflect_Constructor._java_lang_reflect_Constructor_getParameterTypes._ptr)
			local numParamTypes = env:_getArrayLength(paramTypes)

			for j=0,numParamTypes-1 do
				local methodParamType = env:_getObjectArrayElement(paramTypes, j)

				-- String
				local paramClassPath = env:_callObjectMethod(methodParamType, java_lang_Class._java_lang_Class_getTypeName._ptr)

				env:_deleteLocalRef(methodParamType)

				sig:insert(env:_fromJString(paramClassPath))

				env:_deleteLocalRef(paramClassPath)
			end
			env:_deleteLocalRef(paramTypes)

			-- int
			local modifiers = env:_callIntMethod(method, java_lang_reflect_Constructor._java_lang_reflect_Constructor_getModifiers._ptr)
--DEBUG:print('modifiers', modifiers)

			local jmethodID = env:_fromReflectedMethod(method)
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
				class = self._classpath,
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

			_ctors:insert(methodObj)
--DEBUG:print('constructor['..i..'] = '..tolua(sig))
		end

		-- another Java quirk: every function has a default no-arg constructor
		-- but it won't be listed in the java.lang.Class.getDeclaredConstructors() list
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
				_ctors:insert(defaultCtorMethod)
			end
		end
		env:_deleteLocalRef(jobjectCtors)
	end

	-- TODO do I even want to do this?
	-- I can't cache the globalref or Android will fill up its globalrefs...
	-- if I have to lookup the classes by name with classpath$subclassname then why bother even look in advance?
	--[[
	local jobjectClasses = env:_callObjectMethod(self._ptr, java_lang_Class._java_lang_Class_getDeclaredClasses._ptr)
	if jobjectClasses ~= nil then
		io.stderr:write(' !!! DANGER !!! failed to get classes from class '..self._classpath..'\n')
	else
		local numClasses = env:_getArrayLength(jobjectClasses)
		for i=0,numClasses-1 do
			-- just store the names of child classes
		end
		env:_deleteLocalRef(jobjectClasses)
	end
	--]]

	-- determine if this is a SAM class or not
	-- Java says don't SAM abstract-classes.  but then there is all of Swing and JavaFX ...
	--if self._isInterface then
	for name,options in pairs(self._methods) do
		if name ~= '<init>'
		and name ~= '<clinit>'
		then
			-- TODO what will this do on inherited appended methods that accumulate from parent classes?
			for _,option in ipairs(options) do
				-- see if the first method we find is abstract...
				if not self._samMethod then
					if option.isStatic
					then
						-- ignore static
					else
						if not option._isAbstract then
							-- it wasn't abstract, fail
							goto detectSAMDone
						end
						-- write our sam method and see if there are more...
						self._samMethod = option
					end
				else
					-- there were more methods, this isn't SAM, clear it and fail
					self._samMethod = false
					goto detectSAMDone
				end
			end
		end
	end
::detectSAMDone::

	env._ignoringExceptions = pushIgnore
	env:_exceptionClear()


	-- while we're here, I gotta copy all static fields from any interfaces, so I might as well store them too
	local jobjectInterfaces = env:_callObjectMethod(self._ptr, java_lang_Class._java_lang_Class_getInterfaces._ptr)
	if jobjectInterfaces ~= nil then
		local numInterfaces = env:_getArrayLength(jobjectInterfaces)
		for i=0,numInterfaces-1 do
			local jobjectIface = env:_getObjectArrayElement(jobjectInterfaces, i)
			local cl = env:_fromJClass(jobjectIface)
			self._interfaces:insert(cl)
			env:_deleteLocalRef(jobjectIface)
		end
		env:_deleteLocalRef(jobjectInterfaces)
	end


	-- this won't go wrong, will it?
	local jsuper = env:_getSuperclass(self._ptr)
	if jsuper ~= nil then
		local super = env:_fromJClass(jsuper)
		self.super = super
	end

	local function copyMethodsAndFieldsFrom(cl)
--DEBUG:print('has super', self.super._classpath)

		-- and while we're here, merge super's fields and methods into ours

		-- [[ can I just use the same method?
		for name,fields in pairs(cl._fields) do
			self._fields[name] = self._fields[name] or table()
			self._fields[name]:append(fields)
		end
		for name,methods in pairs(cl._methods) do
			self._methods[name] = self._methods[name] or table()
			self._methods[name]:append(methods)
		end
		--]]
	end

	if self.super then
		copyMethodsAndFieldsFrom(self.super)
	end
	for _,iface in ipairs(self._interfaces) do
		copyMethodsAndFieldsFrom(iface)
	end
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
		jmethodID = env:_getStaticMethodID(self._ptr, funcname, sigstr)
	else
		jmethodID = env:_getMethodID(self._ptr, funcname, sigstr)
	end
	-- will this throw an exception? probably.
	if jmethodID == nil then
		local ex = env:_getException()
		return
			nil,
			"failed to find method "..tostring(funcname)
				..(isStatic and ' static' or '')
				..' '..tolua(sigstr),
			ex
	end

	args.env = env
	args.class = self._classpath
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
		jfieldID = env:_getStaticFieldID(self._ptr, fieldname, sigstr)
	else
		jfieldID = env:_getFieldID(self._ptr, fieldname, sigstr)
	end
	if jfieldID == nil then
		local ex = env:_getException()
		return nil, "failed to find jfieldID="..tostring(fieldname)..' sig='..tostring(sig)..(isStatic and ' static' or '')..': '..tostring(ex), ex
	end

	args.env = env
	args.ptr = jfieldID
	args.class = self._classpath
	return JavaField(args)
end

function JavaClass:_new(...)
	-- shorthand for building a class from a Java-lambda equivalent Lua-function
	if type((...)) == 'function' then
		return self:_cb(...)
	end

--[[
	local ctors = table()
	do
		local cl = self
		while cl do
			local methods = rawget(cl, '_methods')['<init>']
			if methods then ctors:append(methods) end
			cl = cl.super
		end
	end
--]]
-- [[
	local ctors = rawget(self, '_methods')['<init>']
--]]
	if not (ctors and #ctors > 0) then
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

-- idk that theres an equivalent operator in java?
-- does instanceof of an object of the class
function JavaClass:_isAssignableFrom(classTo)
	local env = self._env
	if type(classTo) == 'string' then
		local classpath = classTo
		classTo = env:import(classpath)
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
	local canCast = env:_isAssignableFrom(self._ptr, classTo._ptr)
	return canCast ~= 0, classTo
end

-- calls in java `class.getTypeName()`
function JavaClass:_name()
	local env = self._env
	local jstringClasspath = env:_callObjectMethod(self._ptr, env._java_lang_Class._java_lang_Class_getTypeName._ptr)
	if jstringClasspath == nil then return nil end
	local classpath = env:_fromJString(jstringClasspath)
	env:_deleteLocalRef(jstringClasspath)
	return classpath
end

function JavaClass:_throwNew()
	self._env:_throwNew(self._ptr)
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

	--[[ write protect and only allow _ lua vars
	-- don't build namespaces off private vars
	if k:match'^_' then
		print('JavaClass.__index', k, "I am reserving underscores for private variables.  You were about to invoke a name resolve")
		print(debug.traceback())
		return
	end
	--]]

	-- now check fields/methods
--DEBUG:print('here', self._classpath)
--DEBUG:print(require'ext.table'.keys(self._fields):sort():concat', ')
	local fieldsForName = rawget(self, '_fields')[k]
	if fieldsForName then
		-- assert it is a static field?
		local field = fieldsForName[1]
		return field:_get(self)	-- call the getter of the field
	end

--DEBUG:print(require'ext.table'.keys(self._methods):sort():concat', ')
--[[
	local methodsForName = table()
	do
		local cl = self
		while cl do
			local methods = rawget(cl, '_methods')[k]
			if methods then methodsForName:append(methods) end
			cl = cl.super
		end
	end
--]]
-- [[ only this class scope
	local methodsForName = rawget(self, '_methods')[k]
--]]
	if methodsForName and #methodsForName > 0 then
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
	local cl = env:import(classpath)
assert.eq(true, env._ignoringExceptions)
	env._ignoringExceptions = false
	env:_exceptionClear()
	if cl then return cl end
end

--[[
build the subclass used for _cb()
- func = callback
- newLuaState = whether invoking this function should use a new lite-thread and new lua state or not.
--]]
function JavaClass:_cbClass(func, newLuaState)
	local JavaLuaClass = require 'java.luaclass'
	return self:_subclass{
		methods = {
			{
				name = self._samMethod._name,
				sig = self._samMethod._sig,
				isPublic = true,
				value = func,
				newLuaState = newLuaState,
			},
		},
	}
end

function JavaClass:_subclass(args)
	args.env = self._env
	if self._isInterface then
		args.implements = {self._classpath}
	else
		args.extends = self._classpath
	end
	local JavaLuaClass = require 'java.luaclass'
	return JavaLuaClass(args)
end

-- build a subclass of "single-abstract-method" class for a Java-lamdba-equivalent for a Lua-function
function JavaClass:_cb(func, newLuaState, ...)
	return self:_cbClass(func, newLuaState)(...)
end

-- if this calls parent class __tostring, that will call JavaObject:__tostring(), which calls the Java .toString(), but it will be on a jclass pointer...
-- ... which OpenJDK doesn't mind, but Android will segfault because Google is retarded.
-- Google Gemini tells me Android JNI segfaults so much and has so many exceptional cases to their API because "it makes it go faster".  Like speed holes I guess.
function JavaClass:__tostring()
	return self:_getDebugStr()
end

return JavaClass
