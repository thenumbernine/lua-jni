--[[
TODO what should the scope of this class be?
should it be long-term as members of java.class?
if so then I should be giving this GlobalRef's
but as it stands, i'm using too many GlobalRef's and it is overflowing on Android.
so
should this not hold GlobalRef's and just lookup when it finally needs to?
Then this should contain all lookup info ...
what would that be?
- class(name), name, signature.
... same for java.method.

... oh interesting
I'm reading that jfieldID and jmethodID do not need to be unloaded, and they exist until the class is unloaded.
--]]
local class = require 'ext.class'
local assert = require 'ext.assert'
local string = require 'ext.string'
local table = require 'ext.table'
local JavaObject = require 'java.object'
local prims = require 'java.util'.prims


local getNameForType =
	table{'void', 'object'}
	:append(prims)
	:mapi(function(name)
		return 'Get'..name:sub(1,1):upper()..name:sub(2)..'Field', name
	end):setmetatable(nil)

local getStaticNameForType =
	table{'void', 'object'}
	:append(prims)
	:mapi(function(name)
		return 'GetStatic'..name:sub(1,1):upper()..name:sub(2)..'Field', name
	end):setmetatable(nil)

local setNameForType =
	table{'void', 'object'}
	:append(prims)
	:mapi(function(name)
		return 'Set'..name:sub(1,1):upper()..name:sub(2)..'Field', name
	end):setmetatable(nil)

local setStaticNameForType =
	table{'void', 'object'}
	:append(prims)
	:mapi(function(name)
		return 'SetStatic'..name:sub(1,1):upper()..name:sub(2)..'Field', name
	end):setmetatable(nil)


-- subclass of JavaObject?
local JavaField = class()
JavaField.__name = 'JavaField'

function JavaField:init(args)
	self._env = assert.index(args, 'env')		-- JNIEnv
	self._ptr = assert.index(args, 'ptr')		-- cdata
	self._sig = assert.index(args, 'sig')		-- string
	self._name = args.name or false				-- optional but save if provided
	self._class = args.class or false			-- optional but save if provided.  string of class's classpath.

	-- modifiers
	self._isPublic = not not args.isPublic
	self._isPrivate = not not args.isPrivate
	self._isProtected = not not args.isProtected
	self._isStatic = not not args.isStatic
	self._isFinal = not not args.isFinal
	self._isVolatile = not not args.isVolatile
	self._isTransient = not not args.isTransient
	self._isSynthetic = not not args.isSynthetic
	self._isEnum = not not args.isEnum
end

-- there is a case for maintaining these pointers ...
function JavaField:__call(...)
	local n = select('#', ...)
	if n == 1 then
		return self:_get(...)
	elseif n == 2 then
		return self:_set(...)
	else
		error('JavaField __call needs 1 arg for getter, 2 args for setter')
	end
end

function JavaField:_get(thisOrClass)
	local env = self._env

	env:_checkExceptions()

	local getName, getObject
	if self._isStatic then
		getObject = getStaticNameForType.object
		getName = getStaticNameForType[self._sig] or getObject
	else
		getObject = getNameForType.object
		getName = getNameForType[self._sig] or getObject
	end

	local result = env._ptr[0][getName](
		env._ptr,
		assert(env:_luaToJavaArg(thisOrClass)),
		self._ptr
	)

	env:_checkExceptions()

	-- if it's a primitive then return it
	if getName ~= getObject then return result end

	-- if it's nil or NULL then return nil
	if result == nil then return nil end

	return JavaObject._createObjectForClassPath{
		env = env,
		ptr = result,
		classpath = self._sig,
	}
end

function JavaField:_set(thisOrClass, value)
	local env = self._env

	env:_checkExceptions()

	local setName
	if self._isStatic then
		setName = setStaticNameForType[self._sig] or setStaticNameForType.object
	else
		setName = setNameForType[self._sig] or setNameForType.object
	end

	env._ptr[0][setName](
		env._ptr,
		assert(env:_luaToJavaArg(thisOrClass)),
		self._ptr,
		env:_luaToJavaArg(value, self._sig)
	)

	env:_checkExceptions()
end

function JavaField:__tostring()
	return self.__name..'('..tostring(self._ptr)..')'
end

JavaField.__concat = string.concat

return JavaField
