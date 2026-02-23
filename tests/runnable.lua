#!/usr/bin/env luajit
--[[
Java provides no way to handle C functions, apart from its own JNI stuff
This means there's no way to pass in a LuaJIT->C closure callback to Java without going through JNI

How would I have a Java Runnable call a LuaJIT function?

Mind you this is not worrying about multithreading just yet.  Simply Runnable.
--]]

require 'java.tests.nativerunnable'	-- build

local JVM = require 'java.vm'
local jvm = JVM{
	props = {
		['java.class.path'] = '.',
		['java.library.path'] = '.',
	}
}
local J = jvm.jniEnv

print('J.io.github.thenumbernine.NativeRunnable', J.io.github.thenumbernine.NativeRunnable)
print('J.io.github.thenumbernine.NativeRunnable.run', J.io.github.thenumbernine.NativeRunnable.run)
print('J.io.github.thenumbernine.NativeRunnable.runNative', J.io.github.thenumbernine.NativeRunnable.runNative)

callback = function(arg)
	print('hello from within Lua, arg', arg)
end
local ffi = require 'ffi'
closure = ffi.cast('void *(*)(void*)', callback)
J.io.github.thenumbernine.NativeRunnable(closure, 123456789):run()
