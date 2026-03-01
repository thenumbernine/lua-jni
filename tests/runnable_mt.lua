#!/usr/bin/env luajit

-- child thread:

local thread = require 'thread.lite'{
	code = [=[
	local J = require 'java.vm'{ptr=jvmPtr}.jniEnv

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
		['java.library.path'] = '.',
	},
}.jniEnv

--local NativeRunnable = require 'java.tests.nativerunnable'(J)		-- use javac and gcc
--local NativeRunnable = require 'java.tests.nativerunnable_asm'(J)	-- use java-ASM (still needs gcc)
local NativeRunnable = require 'java.tests.nativerunnable_classdata'(J)	-- "WE'LL DO IT LIVE!!!!"

-- before I was passing J._vm._ptr as the arg
-- now I can't because JNI expects it to be jobject and will poke inside the memory
-- I could wrap it in a Long, but then I'd need the VM to decode it,
-- so why not just write the VM pointer this way.
local ffi = require 'ffi'
thread.lua([[ jvmPtr = ... ]], ffi.cast('uint64_t', J._vm._ptr))

local th = J.Thread(NativeRunnable(thread.funcptr))
print('thread', th)
th:start()
th:join()
thread:showErr()
