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


local JavaMethod = class()
JavaMethod.__name = 'JavaMethod'

function JavaMethod:init(args)
	self.env = assert.index(args, 'env')		-- JNIEnv
	self.ptr = assert.index(args, 'ptr')		-- cdata
	self.sig = assert.index(args, 'sig')		-- sig desc is in require 'java.class' for now

	-- TODO I was holding this to pass to CallStatic*Method calls
	-- but I geuss the whole idea of the API is that you can switch what class calls a method (so long as its an appropriate interface/subclass/whatever)
	-- so maybe I don't want .class to be saved.
	self.class = assert.index(args, 'class')	-- JavaClass where the method came from ...

	-- you need to know if its static to load the method
	-- and you need to know if its static to call the method
	-- ... seems that is something that shoudlve been saved with the  method itself ...
	self.static = args.static
end

function JavaMethod:__call(thisOrClass, ...)
	local callName
	if self.static then
		callName = callStaticNameForReturnType[self.sig[1]]
			or callStaticNameForReturnType.object
	else
		callName = callNameForReturnType[self.sig[1]]
			or callNameForReturnType.object
	end
--print('callName', callName)
	-- if it's a static method then a class comes first
	-- otherwise an object comes first
	local result = self.env.ptr[0][callName](
		self.env.ptr,
		assert(self.env:luaToJavaArg(thisOrClass)),	-- if it's a static method ... hmm should I pass self.class by default?
		self.ptr,
		self.env:luaToJavaArgs(...)	-- TODO sig as well to know what to convert it to?
	)
	if self.sig[1] == nil or self.sig[1] == 'void' then return end
	-- convert / wrap the result
	return JavaObject.createObjectForClassPath(
		self.sig[1], {
			env = self.env,
			ptr = result,
			classpath = self.sig[1],
		}
	)
end

-- calls in Java `new classObj(...)`
-- first arg is the ctor's class obj
-- rest are ctor args
-- TODO if I do my own matching of args to stored java reflect methods then I don't need to require the end-user to pick out the ctor method themselves...
function JavaMethod:newObject(classObj, ...)
	local classpath = assert(classObj.classpath)
	local result = self.env.ptr[0].NewObject(
		self.env.ptr,
		self.env:luaToJavaArg(classObj),
		self.ptr,
		self.env:luaToJavaArgs(...)	-- TODO sig as well to know what to convert it to?
	)
	-- fun fact, for java the ctor has return signature 'void'
	-- which means the self.sig[1] won't hvae the expected classpath
	-- which means we have to store/retrieve extra the classpath of the classObj
	return JavaObject.createObjectForClassPath(
		classpath,
		{
			env = self.env,
			ptr = result,
			classpath = assert(classpath),
		}
	)
end

function JavaMethod:__tostring()
	return self.__name..'('..tostring(self.ptr)..')'
end

JavaMethod.__concat = string.concat

return JavaMethod
