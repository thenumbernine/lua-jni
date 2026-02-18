local class = require 'ext.class'
local assert = require 'ext.assert'
local string = require 'ext.string'
local table = require 'ext.table'
local JavaMethod = require 'java.method'
local JavaField = require 'java.field'
local getJNISig = require 'java.util'.getJNISig
local sigStrToObj = require 'java.util'.sigStrToObj
local JavaCallResolve = require 'java.callresolve'


-- is a Java class a Java object?
-- should JavaClass inherit from JavaObject?
local JavaClass = class()
JavaClass.__name = 'JavaClass'

function JavaClass:init(args)
	self._env = assert.index(args, 'env')
--DEBUG:assert(require 'java.jnienv':isa(self._env))
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
--DEBUG:print('calling setupReflect on', self._classpath)
	if self._members then return end	-- or should I warn?
	self._members = {}	-- self._members[fieldname][fieldIndex] = JavaObject of field or member

	local java_lang_Class = assert(env:_findClass'java.lang.Class')
	-- do I need to save these?
	self._javaObjFields = java_lang_Class._java_lang_Class_getFields(self)
	self._javaObjMethods = java_lang_Class._java_lang_Class_getMethods(self)
	self._javaObjConstructors = java_lang_Class._java_lang_Class_getConstructors(self)
--DEBUG:print(self._classpath..' has '..#self._javaObjFields..' fields and '..#self._javaObjMethods..' methods and '..#self._javaObjConstructors..' constructors')

	local java_lang_reflect_Field = env:_findClass'java.lang.reflect.Field'
	local java_lang_reflect_Method = env:_findClass'java.lang.reflect.Method'
	local java_lang_reflect_Constructor = env:_findClass'java.lang.reflect.Constructor'

	-- now convert the fields/methods into a key-based lua-table to integer-based lua-table for each name ...
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
		local fieldClassPath = tostring(java_lang_Class._java_lang_Class_getName(fieldType))
		fieldClassPath = sigStrToObj(fieldClassPath) or fieldClassPath -- convert from sig-name to name-name
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

	-- TODO how does name resolution go? fields or methods first?
	-- I think they shouldn't ever overlap?
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
		local returnTypeClassPath = tostring(java_lang_Class._java_lang_Class_getName(methodReturnType))
		returnTypeClassPath = sigStrToObj(returnTypeClassPath) or returnTypeClassPath -- convert from sig-name to name-name
		sig:insert(returnTypeClassPath)

		local paramType = java_lang_reflect_Method
			._java_lang_reflect_Method_getParameterTypes(
				method
			)
		for j=0,#paramType-1 do
			local methodParamType = paramType[j]
			local paramClassPath = tostring(java_lang_Class._java_lang_Class_getName(methodParamType))
			paramClassPath = sigStrToObj(paramClassPath) or paramClassPath -- convert from sig-name to name-name
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
--DEBUG:print('method['..i..'] = '..name, require'ext.tolua'(sig))
	end

	-- can constructors use JNIEnv.FromReflectedMethod ?
	do
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
				local paramClassPath = tostring(java_lang_Class._java_lang_Class_getName(methodParamType))
				paramClassPath = sigStrToObj(paramClassPath) or paramClassPath -- convert from sig-name to name-name
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
--DEBUG:print('constructor['..i..'] = '..require'ext.tolua'(sig))
		end

		-- another Java quirk: every function has a default no-arg constructor
		-- but it won't be listed in the java.lang.Class.getConstructors() list
		--  unless it was explicitly defined
		if not foundDefaultCtor then
			local defaultCtorMethod = self:_method{name=name, sig={}}
			-- can this ever not exist?
			-- maybe by protecting it or something?
			if defaultCtorMethod then
				ctors:insert(defaultCtorMethod)
			end
		end
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
		classpath = 'java.lang.Class',	--self._classpath,
	}
end

--[[
args:
	name
	sig
		= table of args as slash-separated classpaths,
		first arg is return type
	static = boolean
--]]
function JavaClass:_method(args)
--DEBUG:assert(require 'java.jnienv':isa(self._env))
	self._env:_checkExceptions()

	assert.type(args, 'table')
	local funcname = assert.type(assert.index(args, 'name'), 'string')
	local static = args.static
	local sig = assert.type(assert.index(args, 'sig'), 'table')
	local sigstr = getJNISig(sig)
--DEBUG:print('sigstr', sigstr)

	local method
	if static then
		method = self._env._ptr[0].GetStaticMethodID(self._env._ptr, self._ptr, funcname, sigstr)
	else
		method = self._env._ptr[0].GetMethodID(self._env._ptr, self._ptr, funcname, sigstr)
	end
	-- will this throw an exception? probably.
	if method == nil then
		local ex = self._env:_exceptionOccurred()
		return nil, "failed to find method "..tostring(funcname)..' '..tostring(sigstr)..(static and ' static' or ''), ex
	end
	return JavaMethod{
		env = self._env,
		class = self,
		ptr = method,
		name = funcname,
		sig = sig,
		static = static,
	}
end

function JavaClass:_field(args)
	self._env:_checkExceptions()

	assert.type(args, 'table')
	local fieldname = assert.type(assert.index(args, 'name'), 'string')
	local sig = assert.type(assert.index(args, 'sig'), 'string')
	local sigstr = getJNISig(sig)
	local static = args.static
	local jfieldID
	if static then
		jfieldID = self._env._ptr[0].GetStaticFieldID(self._env._ptr, self._ptr, fieldname, sigstr)
	else
		jfieldID = self._env._ptr[0].GetFieldID(self._env._ptr, self._ptr, fieldname, sigstr)
	end
	if jfieldID == nil then
		local ex = self._env:_exceptionOccurred()
		return nil, "failed to find jfieldID="..tostring(fieldname)..' sig='..tostring(sig)..(static and ' static' or ''), ex
	end
	return JavaField{
		env = self._env,
		ptr = jfieldID,
		sig = sig,
		static = static,
	}
end

-- calls in java `class.getName()`
-- notice, this matches getJNISig(classpath)
-- so java.lang.String will be Ljava/lang/String;
-- and double[] will be [D
function JavaClass:_name()
--DEBUG:print('JavaClass:_name')
--DEBUG:print("getting env:_findClass'java.lang.Class'")
	local classObj = self._env:_findClass'java.lang.Class'
assert('got', classObj)
assert.eq(classObj._classpath, 'java.lang.Class')
--DEBUG:print('JavaClass:_name, classObj for java.lang.Class', classObj)
assert(classObj._java_lang_Class_getName)
	local classpath = classObj._java_lang_Class_getName(self)
--[[ wait, is this a classpath or a signature?
-- how come double[] arrays return [D ?
-- how come String[] arrays return [Ljava/lang/String;
-- but String returns java/lang/String ? ?!?!?!??!?
-- HOW ARE YOU SUPPOSED TO TELL A SIGNATURE VS A CLASSPATH?
print('JavaClass:_name', type(classpath), classpath)
--]]
	classpath = tostring(classpath)
	classpath = sigStrToObj(classpath) or classpath
	return classpath
end

function JavaClass:_new(...)
	local ctors = self._members['<init>']
	if not ctors or #ctors == 0 then
		error("can't new, no constructors present for "..self._classpath)
	else
		-- TODO here and JavaCallResolve, we are translating args multiple times
		-- TODO just do it once
		local ctor = JavaCallResolve.resolve(ctors, self, ...)
		if not ctor then
			error("args mismatch")
		end
		return ctor:_new(self, ...)
	end
end

function JavaClass:_getDebugStr()
	return self.__name..'('
		..tostring(self._classpath)
		..' '
		..tostring(self._ptr)
		..')'
end

function JavaClass:__tostring()
	return self.__name..'('
		..tostring(self._classpath)
		..' '
		..tostring(self._ptr)
		..')'
end

JavaClass.__concat = string.concat

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
		--[[ filter out non-static methods?
		-- no not yet, we want classes to be able to reference their object methods as JavaMethod-objects,
		-- even when not calling them
		membersForName = membersForName:filteri(function(method)
			return method.static
		end)
		if #membersForName == 0 then
			error("tried to call a non-static method from a class: "..k)
		end
		--]]
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
				caller = self,
				options = membersForName,
			}
		else
			error("got a member for field "..k.." with unknown type "..tostring(getmetatable(member).__name))
		end
	end
end

return JavaClass
