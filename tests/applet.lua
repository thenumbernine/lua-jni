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
	JNIEnv * jniEnv;
	JavaVM * jvm;
	pthread_t parentThread;
} ThreadArg;
]]
ffi.cdef(threadArgTypeCode)

local pthread = require 'ffi.req' 'c.pthread'
print('parent thread pthread_self', pthread.pthread_self())

local threadArg = ffi.new'ThreadArg[1]'
threadArg[0].jniEnv = J._ptr
threadArg[0].jvm = J._vm._ptr
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

local jvm = arg.jvm
local jniEnv = arg.jniEnv
local parentThread = arg.parentThread

if parentThread ~= childThread then
	local jniEnvPtrArr = ffi.new('JNIEnv*[1]', jniEnv)
	assert.eq(ffi.C.JNI_OK, jvm[0].AttachCurrentThread(jvm, jniEnvPtrArr, nil))
	jniEnv = jniEnvPtrArr[0]	-- I have to use the new one
end

local J = require 'java.jnienv'{ptr=jniEnv, vm=jvm}


-- finally, our Java thread code:

local JFrame = J.javax.swing.JFrame
local frame = JFrame:_new'HelloWorldSwing'
frame:setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE)

--[[
local JLabel = J.javax.swing.JLabel
local label = JLabel:_new'Hello, World!'
frame:getContentPane():add(label)
--]]

frame:pack()	-- causes "IncompatibleClassChangeError"
frame:setVisible(true)

print'THREAD DONE'
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
--[[ run on a new Java thread
local th = J.java.lang.Thread:_new(runnable)
print('thread', th)
th:start()
th:join()
thread:showErr()
--]]
-- [[ do invokeLater, but that doesnt block, and I am not Java who waits for all threads to finish ...
--J.javax.swing.SwingUtilities:invokeLater(runnable)
-- does this block until ui quit?
-- no?
print('invokeAndWait')
J.javax.swing.SwingUtilities:invokeAndWait(runnable)
print'invokeLater finished'
thread:showErr()
--]]

-- TODO TODO OK OK
-- https://docs.oracle.com/javase/8/docs/api/javax/swing/SwingUtilities.html#invokeAndWait-java.lang.Runnable-
-- this says we ...
-- 1) make the new thread,
-- 2) jump into it, then call invokeAndWait on our new Runnable
-- 3) Runnable goes inside the thread

print'DONE'
