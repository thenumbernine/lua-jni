#!/usr/bin/env luajit
--[[
Java provides no way to handle C functions, apart from its own JNI stuff
This means there's no way to pass in a LuaJIT->C closure callback to Java without going through JNI

How would I have a Java Runnable call a LuaJIT function?

Mind you this is not worrying about multithreading just yet.  Simply Runnable.
--]]

local J = require 'java.vm'{
	props = {
		['java.class.path'] = '.',
		['java.library.path'] = '.',
	},
}.jniEnv

local NativeRunnable = require 'java.tests.nativerunnable'(J)

callback = function(arg)
	print('hello from within Lua, arg', arg)
end
local ffi = require 'ffi'
closure = ffi.cast('void *(*)(void*)', callback)
NativeRunnable(closure, 123456789):run()
