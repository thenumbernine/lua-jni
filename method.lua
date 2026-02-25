local class = require 'ext.class'
local assert = require 'ext.assert'
local string = require 'ext.string'
local tolua = require 'ext.tolua'
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

	-- this is used in java wrt super.call ... is that the only time?
	self._nonvirtual = not not args.nonvirtual

	self._isVarArgs = not not args.isVarArgs
end

function JavaMethod:__call(thisOrClass, ...)
	local env = self._env

	-- I don't want to clear exceptions
	-- but I don't want them messing with my stuff
	-- but I don't want to check exceptiosn twice
	-- but I might as well, to be safe
	env:_checkExceptions()

	local returnType = self._sig[1]
	local callName
	if self._static then
		callName = callStaticNameForReturnType[returnType]
			or callStaticNameForReturnType.object
	elseif self._nonvirtual then
		callName = callNonvirtualNameForReturnType[returnType]
			or callNonvirtualNameForReturnType.object
	else
		callName = callNameForReturnType[returnType]
			or callNameForReturnType.object
	end

--DEBUG:print('callName', callName)

	-- only table.pack our args if necessary
	local result
	if self._isVarArgs then
--DEBUG:print()
--DEBUG:print(self._name)
--DEBUG:print('_sig', tolua(self._sig))
		-- java is a pain in the ass as always
		-- the last arg is the array
		-- so up until the last arg, we do require fixed args
		local numJavaNonVarArgs = #self._sig-2	 -- -1 for return type, -1 for vararg array
--DEBUG:print('numJavaNonVarArgs', numJavaNonVarArgs)
		local numLuaArgs = select('#', ...)
--DEBUG:print('numLuaArgs ', numLuaArgs )
		local javaArgObjs = table()
		for i=1,numJavaNonVarArgs do
--DEBUG:print('converting lua arg', i, 'to java arg', i-1, 'sig', self._sig[i+1])
			javaArgObjs[i] = env:_luaToJavaArg(select(i, ...), self._sig[i+1])
		end

		-- just convert it to an Object[] array, let JNI do the type matching
		-- TODO eventually test each vararg type to the underlying vararg array type
		-- TODO use self._sig:last()'s arraytype's basetype here
		local sigLast = table.last(self._sig)
		local sigVarArgBase = sigLast:match'^(.*)%[%]$'
--DEBUG:print('sigVarArgBase', sigVarArgBase)
		local numVarArgs = numLuaArgs - numJavaNonVarArgs
--DEBUG:print('numVarArgs ', numVarArgs )
		local javaVarArgsObj = env:_newArray(sigVarArgBase, numVarArgs)
		for i=1,numVarArgs do
--DEBUG:print('converting lua arg', numJavaNonVarArgs + i, 'to java vararg index', i-1)
			javaVarArgsObj[i-1] = env:_luaToJavaArg(select(numJavaNonVarArgs + i, ...), sigVarArgBase)
		end

		local jargc = numJavaNonVarArgs
		jargc = jargc + 1
		javaArgObjs[jargc] = env:_luaToJavaArg(javaVarArgsObj, sigLast)

		-- if it's a static method then a class comes first
		-- otherwise an object comes first
		result = env._ptr[0][callName](
			env._ptr,
			assert(env:_luaToJavaArg(thisOrClass)),	-- if it's a static method ... hmm should I pass self._class by default?
			self._ptr,
			table.unpack(javaArgObjs, 1, jargc)
		)
	else
		result = env._ptr[0][callName](
			env._ptr,
			assert(env:_luaToJavaArg(thisOrClass)),	-- if it's a static method ... hmm should I pass self._class by default?
			self._ptr,
			env:_luaToJavaArgs(2, self._sig, ...)	-- TODO sig as well to know what to convert it to?
		)
	end

	env:_checkExceptions()

	return env:_javaToLuaArg(result, returnType)
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
	return JavaObject._createObjectForClassPath{
		env = env,
		ptr = result,
		classpath = assert(classpath),
	}
end

function JavaMethod:__tostring()
	return self.__name..'('
		..tostring(self._ptr)
		..(self._static and ' static' or '')
		..(self._nonvirtual and ' nonvirtual' or '')
		..(self._isVarArgs and ' isVarArgs' or '')
		..' '..tolua(self._sig)
		..')'
end

JavaMethod.__concat = string.concat

return JavaMethod
