--[[
This is a wrapper for an object in Java, i.e. a jobject in JNI
--]]
require 'ext.gc'
local ffi = require 'ffi'
local class = require 'ext.class'
local assert = require 'ext.assert'
local string = require 'ext.string'
local table = require 'ext.table'
local JavaCallResolve = require 'java.callresolve'


local JavaObject = class()
JavaObject.__name = 'JavaObject'

-- TODO I have to break my Lua class model to make the java-interoperability layer compatible.
--JavaObject.new exists but in Java "new" is reserved, and I'm exposing it in my API as ":_new()"
JavaObject.super = nil
JavaObject.class = nil
JavaObject.subclass = nil	-- make room for Java instances with fields named 'subclass'
--JavaObject.isa = nil -- handled in __index
--JavaObject.isaSet = nil -- handled in __index

-- Set to true to convert all jobjects to GlobalRef's upon ctor
--  and DeleteGlobalRef them upon their __gc
-- Set to false to just use LocalRefs, and not __gc them,
--  because in theory Java VM will clean them all itself when we "return from JNI",
--  ... which will never happen of course.
JavaObject._makeGlobalRef = true

-- make some kind of call-scope object that,
-- if someone invokes object.super,
-- then all calls from it are fixed in their scope to that specific class i.e. non-virtual.
-- ... I was expecting '.this' to do the same thing, but lo and behold it doesn't, you can only non-virtual-call the parent-class, not the current-class.  way to go java smh.
-- ... I could also allow for obj.super.field = value etc but nah, what's the point.
-- I will allow .super.super tho
local function makeSuperAccess(args)
	return setmetatable({
		_env = args.env,
		_obj = args.obj,
		_classObj = args.classObj,
	}, {
		__index = function(self,k)
			if type(k) ~= 'string' then return end

			if k == 'super' then
				return makeSuperAccess{
					env = self._env,
					obj = self._obj,
					classObj = self._classObj:_super(),
				}
			end

			local classObj = assert.index(self, '_classObj')
			local methodsForName = classObj._methods[k]
			if methodsForName then
print('super', k, #methodsForName)
				return JavaCallResolve{
					name = k,
					caller = self._obj,
					options = methodsForName,
					classObj = classObj,
				}
			end
		end,
	})
end

function JavaObject:init(args)
	local env = assert.index(args, 'env')
	self._env = env
	local envptr = env._ptr

	local ptr = assert.index(args, 'ptr')

	if ptr == nil then
		error("no nil JavaObjects, just use nil itself")
	end

	local makeGlobalRef = args.globalRef
	if makeGlobalRef == nil then
		makeGlobalRef = self._makeGlobalRef
	end
	if makeGlobalRef then
		self._ptr = env:_newGlobalRef(ptr)
	end

	-- TODO detect if not provided?
	self._classpath = assert.index(args, 'classpath')

-- I would like to always save the class here
-- but for the bootstrap classes, they need to call java functions, which wrap Java object results
-- and those would reach here before the bootstrapping of classes is done,
-- so env:import() wouldn't work
--	self._classObj = self._env:import(self._classpath)

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
				local classObj = self:_getClass()

				local fieldsForName = classObj._fields[k]
				if fieldsForName then
					local field = fieldsForName[1]
					return field:_set(self, v)	-- call the setter of the field
				end

				local methodsForName = classObj._methods[k]
				if methodsForName then
					error("can't overwrite a Java method "..k)
				end
				--[[ write protect and only allow _ lua vars
				error("JavaObject.__newindex("..tostring(k)..', '..tostring(v).."): object is write-protected -- can't write private members afer creation")
				--]]
			end

			-- finally do our write
			rawset(self, k, v)
		end,
	}))
end

-- static helper
function JavaObject._getLuaClassForClassPath(classpath)
	if classpath == 'java.lang.String' then
		return require 'java.string'
	-- I can't tell how I should format the classpath
	elseif classpath:match'^%[' then
		error("dont' use jni signatures for classpaths")
		return require 'java.array'
	elseif classpath:match'%[%]$' then
		return require 'java.array'
	end
	return JavaObject
end

-- static helper function for getting the correct JavaObject subclass depending on the classpath
function JavaObject._createObjectForClassPath(args)
	return JavaObject._getLuaClassForClassPath(args.classpath)(args)
end

-- gets a JavaClass wrapping the java call `obj._getClass()`
-- equivalent to java object.getClass(),
-- but that function returns a java.lang.Object instance of a java.lang.Class class, generic subclass of the class you're looking for
-- while this returns the class that you're looking for
-- though technically obj:getClass() == obj:_getClass():_class() is equivalent to java's `object.getClass()`
function JavaObject:_getClass()
	local env = self._env
	local jclass = env:_getObjectClass(self._ptr)
	local cl = env:_fromJClass(jclass)
	env:_deleteLocalRef(jclass)
	return cl
end

-- shorthand for self:_getClass():_method(args)
-- then again, can I pass a jobject to JNIEnv's GetMethodID ?
function JavaObject:_method(args)
	return self:_getClass():_method(args)
end

-- shorthand
function JavaObject:_field(args)
	return self:_getClass():_field(args)
end

-- calls in java `obj.toString()`
function JavaObject:_javaToString()
	--[[
	-- I'm going to hide exceptions for this too
	-- because it's used internally, specifically, with Lua __tostring
	-- so if you want your Java toString to throw then call obj:toString() and not tostring(obj)
	local env = self._env
	env:_checkExceptions()
	local pushIgnore = env._ignoringExceptions
	env._ignoringExceptions = true
	local javaToString = self.toString
	local str = javaToString and tostring(javaToString(self)) or nil
	env._ignoringExceptions = pushIgnore
	env:_exceptionClear()
	return str
	--]]
	-- [[ and same but without creating a new JavaObject ...

	local env = self._env
	env:_checkExceptions()
	local pushIgnore = env._ignoringExceptions
	env._ignoringExceptions = true

	local str
	do
		local jstring = env:_callObjectMethod(self._ptr, env._java_lang_Object._java_lang_Object_toString._ptr)
		if jstring ~= nil then
			str = env:_fromJString(jstring)
			env:_deleteLocalRef(jstring)
		end
	end

	env._ignoringExceptions = pushIgnore
	env:_exceptionClear()
	return str

	--]]
	--[[ same but throws exceptions in Java
	return tostring(self:toString())
	--]]
end

-- TODO maybe I can call this 'instanceof' anyways since its a reserved-word in Java ...
function JavaObject:instanceof(classTo)
	return self:_getClass():_isAssignableFrom(classTo)
end

function JavaObject:_cast(classTo)
	local can, classTo = self:instanceof(classTo)
	if not can then return end
	return JavaObject{
		env = self._env,
		ptr = self._ptr,
		classpath = classTo._classpath,
	}
end

function JavaObject:throw()
	self._env:throw(self)
end

function JavaObject:_getDebugStr()
	return self.__name..'('
		..tostring(self._classpath)
		..' '
		..tostring(self._ptr)
		..')'
end

function JavaObject:__tostring()
	return self:_javaToString() or self:_getDebugStr()
end

JavaObject.__concat = string.concat

-- uses JNIEnv.IsSameObject
function JavaObject.__eq(a,b)
	local env
	if type(a) == 'table' then
		env = a._env
		a = a._ptr
	end
	if type(b) == 'table' then
		env = env or b._ptr
		b = b._ptr
	end
	assert(env, "tried to use JavaObject to compare two non-JavaObject's")
	-- assert they are cdata or nil ...
	return 0 ~= env:_isSameObject(a, b)
end

function JavaObject:__index(k)
	-- if self[k] exists then this isn't called
	if k ~= 'isa' and k ~= 'isaSet' then
		local cl = getmetatable(self)
		local v = cl[k]
		if v ~= nil then return v end
	end

	if type(k) ~= 'string' then
		-- TODO indexed keys for java.lang.Array's
		return
	end

	if k == 'super' then
		return makeSuperAccess{
			env = self._env,
			obj = self._obj,
			classObj = self:_getClass(),
		}
	end

	--[[ write protect and only allow _ lua vars
	-- don't build namespaces off private vars
	if k:match'^_' then
		print('JavaObject.__index', k, "I am reserving underscores for private variables.  You were about to invoke a name resolve")
		print(debug.traceback())
		return
	end
	--]]

	-- now check fields/methods
	local classObj = self:_getClass()
--DEBUG:print('here', classObj._classpath)
--DEBUG:print(require'ext.table'.keys(classObj._fields):sort():concat', ')
	local fieldsForName = classObj._fields[k]
	if fieldsForName then
		local field = fieldsForName[1]
		return field:_get(self)	-- call the getter of the field
	end

--DEBUG:print(require'ext.table'.keys(classObj._methods):sort():concat', ')
	local methodsForName = classObj._methods[k]
	if methodsForName then
--DEBUG:print('#methodsForName', k, #methodsForName)
		-- now our choice of methodsForName[] will depend on the calling args...
		return JavaCallResolve{
			name = k,
			caller = self,
			options = methodsForName,
		}
	end
end

-- turns out in java `object.class` is just shorthand for `object.getClass()`
-- there is no actual `class` field
-- with that said, I don't think I'll try to replace .class
-- if it's not a field then meh.
-- .class will retain its original Lua class meaning

function JavaObject:_iter()
	-- if we are an Array type then ...
	if self._classpath:match'%[%]$' then
		return coroutine.wrap(function()
			for i=0,#self-1 do
				coroutine.yield(self:_get(i))
			end
		end)
	else
		return coroutine.wrap(function()
			local i = self:iterator()
			while i:hasNext() do
				coroutine.yield(i:next())
			end
		end)
	end
end

function JavaObject:__len()
	local env = self._env
	-- TODO a better array detection
	if self._classpath:match'%[%]$' then
		return env:_getArrayLength(self._ptr)
	elseif self._classpath == 'java.lang.String' then
		-- String is final, so it's ok
		return env:_getStringLength(self._ptr)
	else
		local classObj = self:_getClass()

		local lengthField = classObj._fields.length
		if lengthField then
			return lengthField:_get(self)
		end

		local lengthMethod = classObj._methods.length
		if lengthMethod then
			return self:length()	-- JavaCallResolve
		end

		return 0
	end
end

function JavaObject:__gc()
	local ptr = rawget(self, '_ptr')
	if ptr then
		local env = self._env
		if env then
			local vmptr = env._vm._ptr
			if vmptr
			and vmptr[0] ~= nil
			then
				if env:_getObjectRefType(ptr) == ffi.C.JNIGlobalRefType then
--DEBUG:print('obj shutting down with vm ptr', vmptr, vmptr[0])
					env:_deleteGlobalRef(ptr)
				end
				rawset(self, '_ptr', false)
			end
		end
	end
end

return JavaObject
