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
function JavaClass:_setupReflection()
	local env = self._env

	self._members = {}	-- self._members[fieldname][fieldIndex] = JavaObject of field or member
	
	local java_lang_Class = assert(env:_class'java.lang.Class')
	self._javaObjFields = java_lang_Class._java_lang_Class_getFields(self)
	self._javaObjMethods = java_lang_Class._java_lang_Class_getMethods(self)
--DEBUG:print(self._classpath, 'has', #self._javaObjFields, 'fields and', #self._javaObjMethods, 'methods')
	
	local java_lang_reflect_Field = env:_class'java.lang.reflect.Field'
	local java_lang_reflect_Method = env:_class'java.lang.reflect.Method'
--DEBUG:print('JNIEnv:init java_lang_reflect_Method', java_lang_reflect_Method)	

	-- now convert the fields/methods into a key-based lua-table to integer-based lua-table for each name ...
	for i=0,#self._javaObjFields-1 do
		local field = self._javaObjFields[i]
		local name = tostring(java_lang_reflect_Field
			._java_lang_reflect_Field_getName(
				field
			))
--DEBUG:print('field['..i..'] = '..name, field)
		self._members[name] = self._members[name] or table()
		self._members[name]:insert(field)
	end

	-- TODO how does name resolution go? fields or methods first?
	-- I think they shouldn't ever overlap?
	for i=0,#self._javaObjMethods-1 do
		local method = self._javaObjMethods[i]
		local name = tostring(java_lang_reflect_Method
			._java_lang_reflect_Method_getName(
				method
			))
--DEBUG:print('method['..i..'] = '..name, method)
		self._members[name] = self._members[name] or table()
		self._members[name]:insert(method)
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
	local field
	if static then
		field = self._env._ptr[0].GetStaticFieldID(self._env._ptr, self._ptr, fieldname, sigstr)
	else
		field = self._env._ptr[0].GetFieldID(self._env._ptr, self._ptr, fieldname, sigstr)
	end
	if field == nil then
		local ex = self._env:_exceptionOccurred()
		return nil, "failed to find field "..tostring(fieldname)..' '..tostring(sig)..(static and ' static' or ''), ex
	end
	return JavaField{
		env = self._env,
		ptr = field,
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
