local class = require 'ext.class'
local assert = require 'ext.assert'
local string = require 'ext.string'
local table = require 'ext.table'
local JavaObject = require 'java.object'


-- seems this goes somewhere with the sig stuff in java.class
local prims = table{
	'boolean',
	'byte',
	'char',
	'short',
	'int',
	'long',
	'float',
	'double',

}

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
	self.static = arg.static
end

local function remapArg(arg)
	if type(arg) == 'table' then return arg.ptr end
	return arg
end

local function remapArgs(...)
	if select('#', ...) == 0 then return end
	return remapArg(...), remapArgs(select(2, ...))
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
		assert(remapArg(thisOrClass)),	-- if it's a static method
		self.ptr,
		remapArgs(...)
	)
	-- TODO convert / wrap the result
	local wrapperClass = JavaObject.getWrapper(self.sig[1])
	return wrapperClass{
		env = self.env,
		ptr = result,
		classpath = self.sig[1],
	}
end

function JavaMethod:__tostring()
	return self.__name..'('..tostring(self.ptr)..')'
end

JavaMethod.__concat = string.concat

return JavaMethod
