#!/usr/bin/env luajit

-- child thread:

local thread = require 'thread.lite'{
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

-- parent thread:

local pthread = require 'ffi.req' 'c.pthread'
print('parent thread pthread_self', pthread.pthread_self())

local J = require 'java.vm'{
	props = {
		['java.class.path'] = table.concat({
			'.',
			'asm-9.9.1.jar',		-- needed for ASM
		}, ':'),
	},
}.jniEnv

--local NativeRunnable = require 'java.tests.nativerunnable'(J)		-- use javac and gcc
local NativeRunnable = require 'java.tests.nativerunnable_asm'(J)	-- use java-ASM (still needs gcc)

local th = J.Thread(NativeRunnable(thread.funcptr, J._vm._ptr))
print('thread', th)
th:start()
th:join()
thread:showErr()
