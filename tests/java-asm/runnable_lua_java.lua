#!/usr/bin/env luajit

local J = require 'java.vm'{
	props = {
		['java.class.path'] = table.concat({
			'asm-9.9.1.jar',		-- needed for ASM
		}, ':'),
	},
}.jniEnv

--[[ longwinded
local LuaJavaClassFromSAM = require 'java.tests.java-asm.lua_java_class_from_sam'
local NativeRunnable = LuaJavaClassFromSAM{
	env = J,
	class = J.Runnable,
	func = function(...)
		print('hello from within Lua!', ...)
	end,
}
NativeRunnable():run()
--]]
-- [[ concise
local LuaJavaClass = require 'java.tests.java-asm.lua_java_class'	-- modify JavaClass _new/_cb
J.Runnable(function(...)
	print('hello from within Lua!', ...)
end):run()
--]]
