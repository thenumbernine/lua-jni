--[[
Using lua_java_class to make a SAM subclass
unlike 'make_sam_native_callback_asm', this makes one class per function
--]]
local assert = require 'ext.assert'
local JavaClass = require 'java.class'

local LuaJavaClass = require 'java.tests.lua_java_class'

--[[
args:
	env = env,
	class = JavaClass of single-action-method
	func = callback function to override
--]]
return function(args)
	local env = assert.index(args, 'env')
	local samClass = assert.index(args, 'class')

--DEBUG:print('samClass', samClass)
	assert(JavaClass:isa(samClass), "expected samClass to be a JavaClass")
	local samMethod = samClass._samMethod

	local parentClass, interfaces
	if samClass._isInterface then
		parentClass = 'java.lang.Object'
		interfaces = {samClass._classpath}
	else
		parentClass = samClass._classpath
	end

	local cl = LuaJavaClass{
		env = env,
		extends = parentClass,
		interfaces = interfaces,
		methods = {
			{
				name = samMethod._name,
				sig = samMethod._sig,
				func = args.func,
			},
		},
	}

	return cl
end
