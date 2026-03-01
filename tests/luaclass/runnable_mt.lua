#!/usr/bin/env luajit

-- child thread:
local thread = require 'thread.lite'{
	code = [=[
	local J = require 'java.vm'{ptr=jvmPtr}.jniEnv

	-- TODO how about an easier way to cast a jobject to a JavaObject ?
	local JavaObject = require 'java.object'
	arg = JavaObject._createObjectForClassPath{
		env = J,
		ptr = arg,
		classpath = J:_getObjClassPath(arg), 
	}
	print('hello from child thread Lua, arg', arg)

	print('J', J)
	print('J.System.out', J.System.out)
	J.System.out:println("LuaJIT -> Java -> JNI -> (new thread) -> LuaJIT -> Java -> printing here")

	J:_checkExceptions()
]=],
}

local J = require 'java'

-- how else to forward JVM ptr to child thread Lua state? ...
local ffi = require 'ffi'
thread.lua([[ jvmPtr = ... ]], ffi.cast('uint64_t', J._vm._ptr))

-- auto-cast from func ptr
local th = J.Thread(J.Runnable:_cb(thread.funcptr))
print('thread', th)
th:start()
th:join()
thread:showErr()
