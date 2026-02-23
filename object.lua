local class = require 'ext.class'
local assert = require 'ext.assert'
local string = require 'ext.string'
local table = require 'ext.table'
local JavaCallResolve = require 'java.callresolve'


local JavaObject = class()
JavaObject.__name = 'JavaObject'

-- TODO I have to break my Lua class model to make the java-interoperability layer compatible.
--JavaObject.super exists but in Java ".super" is reserved, and I'm exposing it in my API as ":_super()"
--JavaObject.class exists but in Java ".class" is reserved, and I'm exposing it in my API as ":_class()"
--JavaObject.new exists but in Java "new" is reserved, and I'm exposing it in my API as ":_new()"
JavaObject.subclass = nil	-- make room for Java instances with fields named 'subclass'
--JavaObject.isa ... TODO this is going to hide any "isa" members in Java and get me in trouble...
-- ... but nil-ing it here breaks my class :isa() functionality and my "assert.is" functionality...
--JavaObject.isaSet ... TODO this is going to hide any "isaSet" members in Java ...



function JavaObject:init(args)
	self._env = assert.index(args, 'env')
	self._ptr = assert.index(args, 'ptr')

	-- TODO detect if not provided?
	self._classpath = assert.index(args, 'classpath')

-- I would like to always save the class here
-- but for the bootstrap classes, they need to call java functions, which wrap Java object results
-- and those would reach here before the bootstrapping of classes is done,
-- so env:_findClass() wouldn't work
--	self._classObj = self._env:_findClass(self._classpath)

	-- set our __newindex last after we're done writing to it
	local mt = getmetatable(self)
	setmetatable(self, table(mt, {
		__newindex = function(self, k, v)
			--see if we are trying to write to a Java field
			if type(k) == 'string'
			and not k:match'^_'
			then
				local classObj = self:_getClass()
				local membersForName = classObj._members[k]
				if membersForName then
assert.gt(#membersForName, 0, k)
					local member = membersForName[1]
					local JavaField = require 'java.field'
					local JavaMethod = require 'java.method'
					if JavaField:isa(member) then
						return member:_set(self, v)	-- call the getter of the field
					elseif JavaMethod:isa(member) then
						error("can't overwrite a Java method "..k)
					else
						error("got a member for field "..k.." with unknown type "..tostring(getmetatable(member).__name))
					end
				end
				error("JavaObject.__newindex("..tostring(k)..', '..tostring(v).."): object is write-protected -- can't write private members afer creation")
			end

			-- finally do our write
			rawset(self, k, v)
		end,
	}):setmetatable(nil))
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
	local jclass = env:_getObjClass(self._ptr)
	return env:_getClassForJClass(jclass)
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
	-- [[
	-- I'm going to hide exceptions for this too
	-- because it's used internally, specifically, with Lua __tostring
	-- so if you want your Java toString to throw then call obj:toString() and not tostring(obj)
	local env = self._env
	env:_checkExceptions()
	local pushIgnore = env._ignoringExceptions
	env._ignoringExceptions = true
	local str = tostring(self:toString())
	env._ignoringExceptions = pushIgnore
	env:_exceptionClear()
	return str
	--]]
	--[[ same but throws exceptions in Java
	return tostring(self:toString())
	--]]
end

function JavaObject:_instanceof(classTo)
	return self:_getClass():_isAssignableFrom(classTo)
end

function JavaObject:_cast(classTo)
	local can, classTo = self:_instanceof(classTo)
	if not can then return end
	return JavaObject{
		env = self._env,
		ptr = self._ptr,
		classpath = classTo._classpath,
	}
end

function JavaObject:_throw()
	self._env:_throw(self)
end

function JavaObject:_getDebugStr()
	return self.__name..'('
		..tostring(self._classpath)
		..' '
		..tostring(self._ptr)
		..')'
end

function JavaObject:__tostring()
	return self:_javaToString()
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
	return 0 ~= env._ptr[0].IsSameObject(env._ptr, a, b)
end

function JavaObject:__index(k)
	-- if self[k] exists then this isn't called
	local cl = getmetatable(self)
	local v = cl[k]
	if v ~= nil then return v end

	if type(k) ~= 'string' then
		-- TODO indexed keys for java.lang.Array's
		return
	end

	-- don't build namespaces off private vars
	if k:match'^_' then
		print('JavaObject.__index', k, "I am reserving underscores for private variables.  You were about to invoke a name resolve")
		print(debug.traceback())
		return
	end

	-- now check fields/methods
	local classObj = self:_getClass()
--DEBUG:print('here', classObj._classpath)
--DEBUG:print(require'ext.table'.keys(classObj._members):sort():concat', ')
	local membersForName = classObj._members[k]
	if membersForName then
assert.gt(#membersForName, 0, k)
--DEBUG:print('#membersForName', k, #membersForName)
		-- how to resolve
		-- now if its a field vs a method ...
		local member = membersForName[1]
		local JavaField = require 'java.field'
		local JavaMethod = require 'java.method'
		if JavaField:isa(member) then
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
	local envptr = self._env._ptr
	-- TODO a better array detection
	if self._classpath:match'%[%]$' then
		return envptr[0].GetArrayLength(envptr, self._ptr)
	elseif self._classpath == 'java.lang.String' then
		-- String is final, so it's ok
		return envptr[0].GetStringLength(envptr, self._ptr)
	else
		-- TODO member vs method detect
		local classObj = self:_getClass()
		local length = classObj._members.length
		if not length then return 0 end
		if JavaField:isa(length[1]) then
			return self.length
		elseif JavaMethod:isa(length[1]) then
			return self:length()
		else
			error'???'
		end
	end
end

return JavaObject
