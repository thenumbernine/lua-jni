#!/usr/bin/env luajit
--[[
Needs to be run from java/tests/javac/

Java provides no way to handle C functions, apart from its own JNI stuff
This means there's no way to pass in a LuaJIT->C closure callback to Java without going through JNI

How would I have a Java Runnable call a LuaJIT function?
--]]

local J = require 'java.vm'{
	props = {
		['java.class.path'] = '.',
		['java.library.path'] = '.',
	},
}.jniEnv

local NativeRunnable = require 'java.tests.javac.nativerunnable'(J)		-- use javac and gcc

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
