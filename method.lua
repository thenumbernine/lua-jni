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
	self.class = assert.index(args, 'class')	-- JavaClass
	self.ptr = assert.index(args, 'ptr')		-- cdata
	self.sig = assert.index(args, 'sig')		-- sig desc is in require 'java.class' for now
	
	-- you need to know if its static to load the method
	-- and you need to know if its static to call the method
	-- ... seems that is something that shoudlve been saved with the  method itself ...
	self.static = arg.static
end

local function remapArgs(...)
	if select('#', ...) == 0 then return end
	local arg = ...
	if type(arg) == 'table' then arg = arg.ptr end
	return arg, remapArgs(select(2, ...))
end

function JavaMethod:__call(...)
	local callName
	if self.static then
		callName = callStaticNameForReturnType[self.sig[1]]
			or callStaticNameForReturnType.object
	else
		callName = callNameForReturnType[self.sig[1]]
			or callNameForReturnType.object
	end
	local result = self.env.ptr[0][callName](
		self.env.ptr,
		self.class.ptr,
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
