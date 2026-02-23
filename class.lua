local assert = require 'ext.assert'
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
local JavaClass = JavaObject:subclass()
JavaClass.__name = 'JavaClass'

function JavaClass:init(args)
	self._env = assert.index(args, 'env')
	self._ptr = assert.index(args, 'ptr')
	self._classpath = assert.index(args, 'classpath')

	-- locking namespace for java name resolve,
	-- so define all to-be-used variables here,
	-- even as 'false' for the if-exists tests to fail:
	self._members = false
end

-- call this after creating JavaClass to fill its reflection contents
-- TODO this is using getFields and getMethods
-- should I use getDeclaredFields and getDeclaredMethods ?
-- TODO use JNI invokes throughout here so I don't need to worry about my own Lua object cache / construction stuff going on
function JavaClass:_setupReflection()
	local env = self._env

	-- throw any excpetions occurred so far
	-- because from here on out in setupReflection I will be throwing exceptions away (java.lang.NoSuchMethodError, etc)
	env:_checkExceptions()
	local pushIgnore = env._ignoringExceptions
	env._ignoringExceptions = true

--DEBUG:print('calling setupReflect on', self._classpath)
	if self._members then return end	-- or should I warn?
	self._members = {}	-- self._members[fieldname][fieldIndex] = JavaObject of field or member

	local java_lang_Class = env._java_lang_Class
	local java_lang_reflect_Field = env._java_lang_reflect_Field
	local java_lang_reflect_Method = env._java_lang_reflect_Method
	local java_lang_reflect_Constructor = env._java_lang_reflect_Constructor

	-- do I need to save these?
	self._javaObjFields = java_lang_Class._java_lang_Class_getFields(self)
		or false	-- dont' let these set to nil so that __index wont get angry
	self._javaObjMethods = java_lang_Class._java_lang_Class_getMethods(self)
		or false
	self._javaObjConstructors = java_lang_Class._java_lang_Class_getConstructors(self)
		or false
--DEBUG:print(self._classpath..' has '..#self._javaObjFields..' fields and '..#self._javaObjMethods..' methods and '..#self._javaObjConstructors..' constructors')

	-- now convert the fields/methods into a key-based lua-table to integer-based lua-table for each name ...
	if self._javaObjFields == false then
		io.stderr:write(' !!! DANGER !!! failed to get fields from class '..self._classpath..'\n')
	else
		for i=0,#self._javaObjFields-1 do
			local field = self._javaObjFields[i]

			local name = tostring(java_lang_reflect_Field
				._java_lang_reflect_Field_getName(
					field
				))

			-- fieldType is a jobject ... of a java.lang.Class
			-- can I just treat it like a jclass?
			-- can I just call java.lang.Class.getName() on it?
			-- I guess I can also just do _javaToString and get the same results?
			local fieldType = java_lang_reflect_Field
				._java_lang_reflect_Field_getType(
					field
				)

			local fieldClassPath = tostring(java_lang_Class._java_lang_Class_getTypeName(fieldType))
--DEBUG:print('fieldType', fieldType, fieldClassPath)

			local fieldModifiers = java_lang_reflect_Field
				._java_lang_reflect_Field_getModifiers(
					field
				)
--DEBUG:print('fieldModifiers', fieldModifiers)

			-- ok now switch this reflect field obj to a jni jfieldID
			local jfieldID = env._ptr[0].FromReflectedField(env._ptr, field._ptr)

--DEBUG:print('jfieldID', jfieldID)
			assert(jfieldID ~= nil, "couldn't get jfieldID from reflect field for "..tostring(name))

			local fieldObj = JavaField{
				env = env,
				ptr = jfieldID,
				sig = fieldClassPath,
				static = 0 ~= bit.band(fieldModifiers, 8),	-- java.lang.reflect.Modifier.STATIC
			}

			self._members[name] = self._members[name] or table()
			self._members[name]:insert(fieldObj)
--DEBUG:print('field['..i..'] = '..name, fieldClassPath)
		end
	end

	-- TODO how does name resolution go? fields or methods first?
	-- I think they shouldn't ever overlap?
	if self._javaObjMethods == false then
		io.stderr:write(' !!! DANGER !!! failed to get methods from class '..self._classpath..'\n')
	else
		for i=0,#self._javaObjMethods-1 do
			local method = self._javaObjMethods[i]

			local name = tostring(java_lang_reflect_Method
				._java_lang_reflect_Method_getName(
					method
				))

			local sig = table()

			local methodReturnType = java_lang_reflect_Method
				._java_lang_reflect_Method_getReturnType(
					method
				)

			local returnTypeClassPath = tostring(java_lang_Class._java_lang_Class_getTypeName(methodReturnType))
			sig:insert(returnTypeClassPath)

			local paramType = java_lang_reflect_Method
				._java_lang_reflect_Method_getParameterTypes(
					method
				)

			for j=0,#paramType-1 do
				local methodParamType = paramType[j]

				local paramClassPath = tostring(java_lang_Class._java_lang_Class_getTypeName(methodParamType))
				sig:insert(paramClassPath)
			end

			local modifiers = java_lang_reflect_Method
				._java_lang_reflect_Method_getModifiers(
					method
				)

			local jmethodID = env._ptr[0].FromReflectedMethod(env._ptr, method._ptr)

--DEBUG:print('jmethodID', jmethodID)
			assert(jmethodID ~= nil, "couldn't get jmethodID from reflect method for "..tostring(name))

			local methodObj = JavaMethod{
				env = env,
				ptr = jmethodID,
				name = name,
				sig = sig,
				static = 0 ~= bit.band(modifiers, 8),
			}

			self._members[name] = self._members[name] or table()
			self._members[name]:insert(methodObj)
--DEBUG:print('method['..i..'] = '..name, tolua(sig))
		end
	end

	-- can constructors use JNIEnv.FromReflectedMethod ?
	if self._javaObjConstructors == false then
		io.stderr:write(' !!! DANGER !!! failed to get constructors from class '..self._classpath..'\n')
	else
		local name = '<init>'	-- all constructors have the same name
		self._members[name] = self._members[name] or table()	-- honestly there shouldn't be one here ... unless a constructor got listed as a method, and that would be atypical
		local ctors = self._members[name]
		local foundDefaultCtor
		for i=0,#self._javaObjConstructors-1 do
			local method = self._javaObjConstructors[i]

			local sig = table()
			sig:insert'void'	-- constructor signature has void return type

			local paramType = java_lang_reflect_Constructor
				._java_lang_reflect_Constructor_getParameterTypes(
					method
				)

			for j=0,#paramType-1 do
				local methodParamType = paramType[j]

				local paramClassPath = tostring(java_lang_Class._java_lang_Class_getTypeName(methodParamType))
				sig:insert(paramClassPath)
			end

			local modifiers = java_lang_reflect_Constructor
				._java_lang_reflect_Constructor_getModifiers(
					method
				)

--print('modifiers', modifiers)
			-- NOTICE, ctors do NOT have 'static' flag,
			-- even though  they are supposed to be called with the jclass as the argument (since the object does not yet exist)

			local jmethodID = env._ptr[0].FromReflectedMethod(env._ptr, method._ptr)

--DEBUG:print('jmethodID', jmethodID)
			assert(jmethodID ~= nil, "couldn't get jmethodID from reflect constructor")

			if #sig == 1 and sig[1] == 'void' then
				foundDefaultCtor = true
			end

			local methodObj = JavaMethod{
				env = env,
				ptr = jmethodID,
				name = name,
				sig = sig,
				static = 0 ~= bit.band(modifiers, 8),
			}

			ctors:insert(methodObj)
--DEBUG:print('constructor['..i..'] = '..tolua(sig))
		end

		-- another Java quirk: every function has a default no-arg constructor
		-- but it won't be listed in the java.lang.Class.getConstructors() list
		--  unless it was explicitly defined
		if not foundDefaultCtor then
--DEBUG:print('getting default ctor of class', self._classpath)
			-- sometimes the default isn't there, like in java.lang.Class ...
			local defaultCtorMethod = self:_method{
				name = name,
				sig = {},
			}

			-- can this ever not exist?
			-- maybe by protecting it or something?
			if defaultCtorMethod then
				ctors:insert(defaultCtorMethod)
			end
		end
	end

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
		= table of args as slash-separated classpaths,
		first arg is return type
	static = boolean
	nonvirtual = boolean
--]]
function JavaClass:_method(args)
	local env = self._env

	env:_checkExceptions()

	assert.type(args, 'table')
	local funcname = assert.type(assert.index(args, 'name'), 'string')
	local static = args.static
	local nonvirtual = args.nonvirtual
	local sig = assert.type(assert.index(args, 'sig'), 'table')
	local sigstr = getJNISig(sig)
--DEBUG:print('sigstr', sigstr)

	local method
	if static then
		method = env._ptr[0].GetStaticMethodID(env._ptr, self._ptr, funcname, sigstr)
	else
		method = env._ptr[0].GetMethodID(env._ptr, self._ptr, funcname, sigstr)
	end
	-- will this throw an exception? probably.
	if method == nil then
		local ex = env:_exceptionOccurred()
		return nil, "failed to find method "..tostring(funcname)..' '..tostring(sigstr)
			..(static and ' static' or '')
			..(nonvirtual and ' nonvirtual' or ''),
			ex
	end
	return JavaMethod{
		env = env,
		class = self,
		ptr = method,
		name = funcname,
		sig = sig,
		static = static,
		nonvirtual = nonvirtual,
	}
end

function JavaClass:_field(args)
	local env = self._env

	env:_checkExceptions()

	assert.type(args, 'table')
	local fieldname = assert.type(assert.index(args, 'name'), 'string')
	local sig = assert.type(assert.index(args, 'sig'), 'string')
	local sigstr = getJNISig(sig)
	local static = args.static
	local jfieldID
	if static then
		jfieldID = env._ptr[0].GetStaticFieldID(env._ptr, self._ptr, fieldname, sigstr)
	else
		jfieldID = env._ptr[0].GetFieldID(env._ptr, self._ptr, fieldname, sigstr)
	end
	if jfieldID == nil then
		local ex = env:_exceptionOccurred()
		return nil, "failed to find jfieldID="..tostring(fieldname)..' sig='..tostring(sig)..(static and ' static' or ''), ex
	end
	return JavaField{
		env = env,
		ptr = jfieldID,
		sig = sig,
		static = static,
	}
end

function JavaClass:_new(...)
	local ctors = self._members['<init>']
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
	return env:_getClassForJClass(jsuper)
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
		classTo = env:_getClassForJClass(classTo)
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

-- calls in java `class.getName()`
-- notice, this matches getJNISig(classpath)
-- so java.lang.String will be Ljava/lang/String;
-- and double[] will be [D
function JavaClass:_name()
--DEBUG:print('JavaClass:_name')
--DEBUG:print("getting env:_findClass'java.lang.Class'")
	local classObj = self._env._java_lang_Class
--DEBUG:print('JavaClass:_name, classObj for java.lang.Class', classObj)
	local classpath = classObj._java_lang_Class_getTypeName(self)
	if classpath == nil then return nil end
	return tostring(classpath)
end

function JavaClass:_throwNew()
	self._env:_throwNew(self)
end

function JavaClass:__index(k)

	-- if self[k] exists then this isn't called
	local cl = getmetatable(self)
	local v = cl[k]
	if v ~= nil then return v end

	if type(k) ~= 'string' then return end

	-- don't build namespaces off private vars
	if k:match'^_' then
		print('JavaClass.__index', k, "I am reserving underscores for private variables.  You were about to invoke a name resolve")
		print(debug.traceback())
		return
	end

	-- now check fields/methods
--DEBUG:print('here', self._classpath)
--DEBUG:print(require'ext.table'.keys(self._members):sort():concat', ')
	local membersForName = self._members[k]
	if membersForName then
		assert.gt(#membersForName, 0, k)	-- otherwise the entry shouldn't be there...
--DEBUG:print('#membersForName', k, #membersForName)
		-- how to resolve
		-- now if its a field vs a method ...
		local member = membersForName[1]
		local JavaField = require 'java.field'
		local JavaMethod = require 'java.method'
		if JavaField:isa(member) then
			-- assert it is a static member?
			return member:_get(self)	-- call the getter of the field
		elseif JavaMethod:isa(member) then
			-- now our choice of membersForName[] will depend on the calling args...
			return JavaCallResolve{
				name = k,
				caller = self,
				options = membersForName,
			}
		else
			error("got a member for field "..k.." with unknown type "..tostring(getmetatable(member).__name))
		end
	end
end

return JavaClass
