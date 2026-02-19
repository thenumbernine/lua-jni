#!/usr/bin/env luajit
-- TODO TODO OK OK
-- https://docs.oracle.com/javase/8/docs/api/javax/swing/SwingUtilities.html#invokeAndWait-java.lang.Runnable-
-- this says we ...
-- 1) make the new thread,
-- 2) jump into it, then call invokeAndWait on our new Runnable
-- 3) Runnable goes inside the thread
-- that means one Lua/C callback for the new thread creation, and one callback for the runnable ... two callbacks ...

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

local LiteThread = require 'thread.lite'
local thread = LiteThread{
	arg = threadArg,
	code = [=[
	local J = require 'java.vm'{ptr=arg}.jniEnv

	print('in swing invoke thread...')
	print('testing new object creation...', J:_str("testing testing"))

	local LiteThread = require 'thread.lite'
	local swingThread = LiteThread{
		code = [==[
		local J = require 'java.vm'{ptr=arg}.jniEnv

		print('in swing ui setup thread...')
		print('testing new object creation...', J:_str("testing testing"))

		local JFrame = J.javax.swing.JFrame
		print('JFrame', JFrame)
		local frame = JFrame:_new'HelloWorldSwing'
		print('frame', frame)
		frame:setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE)

		--[[
		print('creating JLabel...')
		local JLabel = J.javax.swing.JLabel
		local label = JLabel:_new'Hello, World!'
		frame:getContentPane():add(label)
		--]]

		print('frame:pack()...')
		frame:pack()	-- causes "IncompatibleClassChangeError"
		print('frame:setVisible(true)...')
		frame:setVisible(true)

		print'SWING UI SETUP THREAD DONE'
	]==],
	}

	print('creating TestNativeRunnable for swing ui setup thread...')
	assert(swingThread.funcptr, 'swingThread.funcptr')
	assert(J._vm._ptr, 'J._vm._ptr')
	local swingUISetupRunnable = J.TestNativeRunnable:_new(swingThread.funcptr, J._vm._ptr)

	print('calling SwingUtilities:invokeAndWait on', swingUISetupRunnable)
	J.javax.swing.SwingUtilities:invokeAndWait(swingUISetupRunnable)
	swingThread:showErr()

	print'INVOKE AND WAIT THREAD DONE'
]=],
}

print('creating TestNativeRunnable for swing invoke thread...')
assert(thread.funcptr, 'thread.funcptr')
assert(J._vm._ptr, 'J._vm._ptr')
local swingInvokeAndWaitRunnable = J.TestNativeRunnable:_new(thread.funcptr, J._vm._ptr)

print('creating java Thread...')
local th = J.java.lang.Thread:_new(swingInvokeAndWaitRunnable)
print('thread', th)
th:start()
th:join()
thread:showErr()

print'DONE'
