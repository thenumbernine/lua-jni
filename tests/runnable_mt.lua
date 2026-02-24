#!/usr/bin/env luajit

-- build
require 'java.tests.nativerunnable'

local JVM = require 'java.vm'
local jvm = JVM{
	props = {
		['java.class.path'] = '.',
		['java.library.path'] = '.',
	}
}

local pthread = require 'ffi.req' 'c.pthread'
print('parent thread pthread_self', pthread.pthread_self())

local LiteThread = require 'thread.lite'
local thread = LiteThread{
	code = [=[
	local J = require 'java.vm'{ptr=arg}.jniEnv

	local pthread = require 'ffi.req' 'c.pthread'
	local childThread = pthread.pthread_self()
	print('child thread, pthread_self', childThread)

	print('hello from child thread Lua, arg', arg)

	print('J', J)
	print('J.System.out', J.System.out)

	J.System.out:println("LuaJIT -> Java -> JNI -> (new thread) -> LuaJIT -> Java -> printing here")

	J:_checkExceptions()
]=],
}

local J = jvm.jniEnv
local th = J.Thread:_new(J.io.github.thenumbernine.NativeRunnable:_new(thread.funcptr, J._vm._ptr))
print('thread', th)
th:start()
th:join()
thread:showErr()
