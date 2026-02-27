#!/usr/bin/env luajit

local J = require 'java.vm'{
	props = {
		['java.class.path'] = table.concat({
			'asm-9.9.1.jar',		-- needed for ASM
		}, ':'),
	},
}.jniEnv

local LuaJavaClassFromSAM = require 'java.tests.lua_java_class_from_sam'
local NativeRunnable = LuaJavaClassFromSAM{
	env = J,
	class = J.Runnable,
	func = function(...)
		print('hello from within Lua!', ...)
	end,
}
NativeRunnable():run()
