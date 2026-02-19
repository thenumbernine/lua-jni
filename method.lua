local class = require 'ext.class'
local assert = require 'ext.assert'
local string = require 'ext.string'
local table = require 'ext.table'
local JavaObject = require 'java.object'
local prims = require 'java.util'.prims


local callNameForReturnType =
	table{'void', 'object'}
	:append(prims)
	:mapi(function(name)
		return 'Call'..name:sub(1,1):upper()..name:sub(2)..'Method', name
	end):setmetatable(nil)

local callNonvirtualNameForReturnType =
	table{'void', 'object'}
	:append(prims)
	:mapi(function(name)
		return 'CallNonvirtual'..name:sub(1,1):upper()..name:sub(2)..'Method', name
	end):setmetatable(nil)

local callStaticNameForReturnType =
	table{'void', 'object'}
	:append(prims)
	:mapi(function(name)
		return 'CallStatic'..name:sub(1,1):upper()..name:sub(2)..'Method', name
	end):setmetatable(nil)


-- subclass of JavaObject?
local JavaMethod = class()
JavaMethod.__name = 'JavaMethod'

function JavaMethod:init(args)
	self._env = assert.index(args, 'env')		-- JNIEnv
	self._ptr = assert.index(args, 'ptr')		-- cdata
	self._sig = args.sig or {}					-- sig desc is in require 'java.class' for now
	self._sig[1] = self._sig[1] or 'void'
	self._name = assert.type(assert.index(args, 'name'), 'string')
	self._isCtor = self._name == '<init>'

	-- TODO I was holding this to pass to CallStatic*Method calls
	-- but I geuss the whole idea of the API is that you can switch what class calls a method (so long as its an appropriate interface/subclass/whatever)
	-- so maybe I don't want .class to be saved.
	--self._class = assert.index(args, 'class')	-- JavaClass where the method came from ...

	-- you need to know if its static to load the method
	-- and you need to know if its static to call the method
	-- ... seems that is something that shoudlve been saved with the  method itself ...
	self._static = not not args.static
end

function JavaMethod:__call(thisOrClass, ...)
	local env = self._env

	-- I don't want to clear exceptions
	-- but I don't want them messing with my stuff
	-- but I don't want to check exceptiosn twice
	-- but I might as well, to be safe
	env:_checkExceptions()

	local callName, returnVoid, returnBool, returnObject
	if self._static then
		returnVoid = callStaticNameForReturnType.void
		returnBool = callStaticNameForReturnType.boolean
		returnObject = callStaticNameForReturnType.object
		callName = callStaticNameForReturnType[self._sig[1]] or returnObject
	else
		returnVoid = callNameForReturnType.void
		returnBool = callNameForReturnType.boolean
		returnObject = callNameForReturnType.object
		callName = callNameForReturnType[self._sig[1]] or returnObject
	end
--print('callName', callName)
	-- if it's a static method then a class comes first
	-- otherwise an object comes first
	local result = env._ptr[0][callName](
		env._ptr,
		assert(env:_luaToJavaArg(thisOrClass)),	-- if it's a static method ... hmm should I pass self._class by default?
		self._ptr,
		env:_luaToJavaArgs(2, self._sig, ...)	-- TODO sig as well to know what to convert it to?
	)

	env:_checkExceptions()

	if callName == returnVoid then return end
	if callName == returnBool then
		return result ~= 0
	end
	if callName ~= returnObject then return result end

	-- if Java returned null then return Lua nil
	-- ... if the JNI is returning null object results as NULL pointers ...
	-- ... and the JNI itself segfaults when it gets passed a NULl that it doesn't like ...
	-- ... where else do I have to bulletproof calls to the JNI?
	if result == nil then
		return nil
	end

	-- convert / wrap the result
	return JavaObject._createObjectForClassPath(
		self._sig[1],
		{
			env = env,
			ptr = result,
			classpath = self._sig[1],
		}
	)
end

-- calls in Java `new classObj(...)`
-- first arg is the ctor's class obj
-- rest are ctor args
-- TODO if I do my own matching of args to stored java reflect methods then I don't need to require the end-user to pick out the ctor method themselves...
function JavaMethod:_new(classObj, ...)
	local env = self._env
	local classpath = assert(classObj._classpath)
	local result = env._ptr[0].NewObject(
		env._ptr,
		env:_luaToJavaArg(classObj),
		self._ptr,
		env:_luaToJavaArgs(2, self._sig, ...)	-- TODO sig as well to know what to convert it to?
	)
	-- fun fact, for java the ctor has return signature 'void'
	-- which means the self._sig[1] won't hvae the expected classpath
	-- which means we have to store/retrieve extra the classpath of the classObj
	return JavaObject._createObjectForClassPath(
		classpath,
		{
			env = env,
			ptr = result,
			classpath = assert(classpath),
		}
	)
end

function JavaMethod:__tostring()
	return self.__name..'('..tostring(self._ptr)..')'
end

JavaMethod.__concat = string.concat

return JavaMethod
