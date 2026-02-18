#!/usr/bin/env luajit
--[[
Java provides no way to handle C functions, apart from its own JNI stuff
This means there's no way to pass in a LuaJIT->C closure callback to Java without going through JNI

How would I have a Java Runnable call a LuaJIT function?

Mind you this is not worrying about multithreading just yet.  Simply Runnable.
--]]
local os = require 'ext.os'

-- build the jni 
require 'make.targets'():add{
	dsts = {'librunnable_lib.so'},
	srcs = {'runnable_lib.c'},
	rule = function(r)
		assert(os.exec('gcc -I"$JAVA_HOME/include" -I"$JAVA_HOME/include/linux" -shared -fPIC -o '..r.dsts[1]..' '..r.srcs[1]))
	end,
}:runAll()

-- build java
require 'make.targets'():add{
	dsts = {'TestNativeRunnable.class'},
	srcs = {'TestNativeRunnable.java'},
	rule = function(r)
		assert(os.exec('javac '..r.srcs[1]))
	end,
}:runAll()

-- weird
-- the jvm is getting the option -Djava.library.path=.
-- it's running
-- it's not finding
local JVM = require 'java.vm'
local jvm = JVM{
	props = {
		['java.class.path'] = '.',
		['java.library.path'] = '.',
	}
}
local J = jvm.jniEnv

-- this loads librunnable_lib.so
-- so this can be used as an entry point for Java->JNI->LuaJIT code
print('J.TestNativeRunnable', J.TestNativeRunnable)
print('J.TestNativeRunnable.run', J.TestNativeRunnable.run)
print('J.TestNativeRunnable.runNative', J.TestNativeRunnable.runNative)

-- I'd return something, but
callback = function(arg)
	print('hello from within Lua, arg', arg)
end
local ffi = require 'ffi'
closure = ffi.cast('void *(*)(void*)', callback)	-- using a pthread signature here and in runnable_lib.c
J.TestNativeRunnable:_new(ffi.cast('jlong', closure)):run()


-- can I do the same thing but without a trampoline class?
-- maybe with java.lang.reflect.Proxy?
-- probably yes up until I try to cross the native C call bridge.

local Runnable = J.java.lang.Runnable
print('Runnable', Runnable)
