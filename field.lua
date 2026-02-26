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

	-- modifiers
	self._isPublic = not not args.isPublic
	self._isPrivate = not not args.isPrivate
	self._isProtected = not not args.isProtected
	self._isStatic = not not args.isStatic
	self._isFinal = not not args.isFinal
	self._isSynchronized = not not args.isSynchronized
	self._isVolatile = not not args.isVolatile
	self._isTransient = not not args.isTransient
	self._isNative = not not args.isNative
	self._isInterface = not not args.isInterface
	self._isAbstract = not not args.isAbstract
	self._isStrict = not not args.isStrict
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

	local getName, returnObject
	if self._isStatic then
		returnObject = getStaticNameForType.object
		getName = getStaticNameForType[self._sig] or returnObject
	else
		returnObject = getNameForType.object
		getName = getNameForType[self._sig] or returnObject
	end

	local result = env._ptr[0][getName](
		env._ptr,
		assert(env:_luaToJavaArg(thisOrClass)),
		self._ptr
	)

	env:_checkExceptions()

	if getName ~= returnObject then return result end

	return JavaObject._createObjectForClassPath{
		env = env,
		ptr = result,
		classpath = self._sig,
	}
end

function JavaField:_set(thisOrClass, value)
	local env = self._env

	env:_checkExceptions()

	local setName, returnObject
	if self._isStatic then
		returnObject = setStaticNameForType.object
		setName = setStaticNameForType[self._sig] or returnObject
	else
		returnObject = setNameForType.object
		setName = setNameForType[self._sig] or returnObject
	end

	local result = env._ptr[0][setName](
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
