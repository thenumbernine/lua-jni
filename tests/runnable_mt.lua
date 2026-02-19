#!/usr/bin/env luajit
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

local JVM = require 'java.vm'
local jvm = JVM{
	props = {
		['java.class.path'] = '.',
		['java.library.path'] = '.',
	}
}
local J = jvm.jniEnv

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
	print('J.java', J.java)
	print('J.java.lang', J.java.lang)
	print('J.java.lang.System', J.java.lang.System)
	print('J.java.lang.System.out', J.java.lang.System.out)

	J.java.lang.System.out:println("LuaJIT -> Java -> JNI -> (new thread) -> LuaJIT -> Java -> printing here")

	J:_checkExceptions()
]=],
}

local th = J.java.lang.Thread:_new(
	J.TestNativeRunnable:_new(thread.funcptr, J._vm._ptr)
)
print('thread', th)
th:start()
th:join()
thread:showErr()
