#!/usr/bin/env luajit
--[[
Java provides no way to handle C functions, apart from its own JNI stuff
This means there's no way to pass in a LuaJIT->C closure callback to Java without going through JNI

How would I have a Java Runnable call a LuaJIT function?
--]]

local J = require 'java.vm'{
	props = {
		['java.class.path'] = table.concat({
			'.',
			'asm-9.9.1.jar',		-- needed for ASM
		}, ':'),
		['java.library.path'] = '.',
	},
}.jniEnv

--local NativeRunnable = require 'java.tests.nativerunnable'(J)		-- use javac and gcc
local NativeRunnable = require 'java.tests.nativerunnable_asm'(J)	-- use java-ASM (still needs gcc)

local ffi = require 'ffi'
callback = function(arg)
	arg = J:_javaToLuaArg(arg, 'java.lang.Long')
	print('hello from within Lua, arg', arg)
end
closure = ffi.cast('void *(*)(void*)', callback)
NativeRunnable(
	closure,
	J.Long:valueOf(123456789)
):run()
