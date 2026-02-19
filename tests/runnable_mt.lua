#!/usr/bin/env luajit
local ffi = require 'ffi'
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

local threadArgTypeCode = [[
typedef struct ThreadArg {
	JNIEnv * jniEnvPtr;
	JavaVM * jvmPtr;
	pthread_t parentThread;
} ThreadArg;
]]
ffi.cdef(threadArgTypeCode)

local pthread = require 'ffi.req' 'c.pthread'
print('parent thread pthread_self', pthread.pthread_self())

local threadArg = ffi.new'ThreadArg[1]'
threadArg[0].jniEnvPtr = J._ptr
threadArg[0].jvmPtr = J._vm._ptr
threadArg[0].parentThread = pthread.pthread_self()

local LiteThread = require 'thread.lite'
local thread = LiteThread{
	arg = threadArg,
	code = [=[
local ffi = require 'ffi'
local assert = require 'ext.assert'
local pthread = require 'ffi.req' 'c.pthread'
require 'java.ffi.jni'	-- needed before ffi.cdef

ffi.cdef[[]=]..threadArgTypeCode..[=[]]
arg = ffi.cast('ThreadArg*', arg)
local childThread = pthread.pthread_self()
print('child thread, pthread_self', childThread)

print('hello from child thread Lua, arg', arg)
local jvmPtr = arg.jvmPtr
print('jvmPtr', jvmPtr)
local jniEnvPtr = arg.jniEnvPtr
print('jniEnvPtr', jniEnvPtr)
local parentThread = arg.parentThread
print('parentThread', parentThread)


-- does jvm.GetEnv give the old or new env?
-- the new env
-- so there's no need to AttachThread
-- (so long as its a thread made by Java)
-- and there's no need to pass the JNIEnv ...
do
	local jniEnvPtrArr = ffi.new('JNIEnv*[1]', nil)
	assert.eq(ffi.C.JNI_OK, jvmPtr[0].GetEnv(jvmPtr, ffi.cast('void**', jniEnvPtrArr), ffi.C.JNI_VERSION_1_6))
	print('jvmPtr GetEnv', jniEnvPtrArr[0])
end

-- does the old env's GetJavaVM work?
-- does the new env's GetJavaVM work?


if parentThread ~= childThread then
print("attaching JVM to new thread...")
	local jniEnvPtrArr = ffi.new('JNIEnv*[1]', jniEnvPtr)
	assert.eq(ffi.C.JNI_OK, jvmPtr[0].AttachCurrentThread(jvmPtr, jniEnvPtrArr, nil))
print('jniEnvPtr after AttachCurrentThread', jniEnvPtrArr[0])
	jniEnvPtr = jniEnvPtrArr[0]	-- I have to use the new one
end

local J = require 'java.jnienv'{
	ptr = jniEnvPtr,
	vm = jvmPtr,
}
-- reverse-order, create the JVM object from the JNIEnv object
J._vm = setmetatable({
	jniEnv = J,
	_ptr = jvmPtr,
	destroy = function() end,
}, require 'java.vm')


-- TODO everything above here can be put inside a JavaThread class
-- too bad it is dependent on the TestNativeRunnable java class to be there ...
-- ... would be nice to do it without any extra Java.


print('J', J)
print('J.java', J.java)
print('J.java.lang', J.java.lang)
print('J.java.lang.System', J.java.lang.System)
print('J.java.lang.System.out', J.java.lang.System.out)

J.java.lang.System.out:println("LuaJIT -> Java -> JNI -> (new thread) -> LuaJIT -> Java -> printing here")
print('exceptions so far?', jniEnvPtr[0].ExceptionOccurred(jniEnvPtr))
]=],
}

local runnable = J.TestNativeRunnable:_new(
	ffi.cast('jlong', thread.funcptr),
	ffi.cast('jlong', ffi.cast('void*', threadArg+0))
)

--[[ run in same thread and quit - for testing
runnable:run()
thread:showErr()
--]]
-- [[ run on a new Java thread
local th = J.java.lang.Thread:_new(runnable)
print('thread', th)
th:start()
th:join()
thread:showErr()
--]]
