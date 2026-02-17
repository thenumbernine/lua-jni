local class = require 'ext.class'
local assert = require 'ext.assert'
local string = require 'ext.string'
local table = require 'ext.table'
local JavaMethod = require 'java.method'
local JavaField = require 'java.field'
local getJNISig = require 'java.util'.getJNISig
local sigStrToObj = require 'java.util'.sigStrToObj

-- is a Java class a Java object?
-- should JavaClass inherit from JavaObject?
local JavaClass = class()
JavaClass.__name = 'JavaClass'

function JavaClass:init(args)
	self._env = assert.index(args, 'env')
--DEBUG:assert(require 'java.jnienv':isa(self._env))
	self._ptr = assert.index(args, 'ptr')
	self._classpath = assert.index(args, 'classpath')
end

-- call this after creating JavaClass to fill its reflection contents
-- TODO this is using getFields and getMethods
-- should I use getDeclaredFields and getDeclaredMethods ?
-- TODO use JNI invokes throughout here so I don't need to worry about my own Lua object cache / construction stuff going on
function JavaClass:_setupReflection()
	local env = self._env
--DEBUG:print('calling setupReflect on', self._classpath)
	self._members = {}	-- self._members[fieldname][fieldIndex] = JavaObject of field or member
	
	local java_lang_Class = assert(env:_class'java.lang.Class')
	self._javaObjFields = java_lang_Class._java_lang_Class_getFields(self)
	self._javaObjMethods = java_lang_Class._java_lang_Class_getMethods(self)
print(self._classpath, 'has', #self._javaObjFields, 'fields and', #self._javaObjMethods, 'methods')
	
	local java_lang_reflect_Field = env:_class'java.lang.reflect.Field'
	local java_lang_reflect_Method = env:_class'java.lang.reflect.Method'

	-- now convert the fields/methods into a key-based lua-table to integer-based lua-table for each name ...
	for i=0,#self._javaObjFields-1 do
		local field = self._javaObjFields[i]
		local name = tostring(java_lang_reflect_Field
			._java_lang_reflect_Field_getName(
				field
			))
print('field['..i..'] = '..name)
		
		-- fieldType is a jobject ... of a java.lang.Class
		-- can I just treat it like a jclass?
		-- can I just call java.lang.Class.getName() on it?
		-- I guess I can also just do _javaToString and get the same results?
		local fieldType = java_lang_reflect_Field
			._java_lang_reflect_Field_getType(
				field
			)
		local fieldClassPath = tostring(java_lang_Class._java_lang_Class_getName(fieldType))
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
	end

	-- TODO how does name resolution go? fields or methods first?
	-- I think they shouldn't ever overlap?
	for i=0,#self._javaObjMethods-1 do
		local method = self._javaObjMethods[i]
		local name = tostring(java_lang_reflect_Method
			._java_lang_reflect_Method_getName(
				method
			))
print('method['..i..'] = '..name, method)
	
		local sig = table()
		local methodReturnType = java_lang_reflect_Method
			._java_lang_reflect_Method_getReturnType(
				method
			)
		local methodReturnTypeName = tostring(java_lang_Class._java_lang_Class_getName(methodReturnType))
		sig:insert(methodReturnTypeName) 
		
		local methodParameterTypes = java_lang_reflect_Method
			._java_lang_reflect_Method_getParameterTypes(
				method
			)
		for j=0,#methodParameterTypes-1 do
			local methodParamType = methodParameterTypes[j]
			local methodParamTypeName = tostring(java_lang_Class._java_lang_Class_getName(methodParamType))
			sig:insert(methodParamTypeName)
		end

		local methodModifiers = java_lang_reflect_Method
			._java_lang_reflect_Method_getModifiers(
				method
			)
		
		local jmethodID = env._ptr[0].FromReflectedMethod(env._ptr, method._ptr)
--DEBUG:print('jmethodID', jmethodID)
		assert(jmethodID ~= nil, "couldn't get jmethodID from reflect method for "..tostring(name))
	
		local methodObj = JavaMethod{
			env = env,
			ptr = jmethodID,
			sig = sig,
			static = 0 ~= bit.band(methodModifiers, 8),
		}
		self._members[name] = self._members[name] or table()
		self._members[name]:insert(methodObj)
	end
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
		return nil, "failed to find jfieldID "..tostring(fieldname)..' '..tostring(sig)..(static and ' static' or ''), ex
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
--DEBUG:print("getting env:_class'java.lang.Class'")
	local classObj = self._env:_class'java.lang.Class'
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

return JavaClass
