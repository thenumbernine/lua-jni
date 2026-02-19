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

local LiteThread = require 'thread.lite'
local thread = LiteThread{
	code = [=[
	local J = require 'java.vm'{ptr=arg}.jniEnv

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
local runnable = J.TestNativeRunnable:_new(thread.funcptr, J._vm._ptr)
--[[ run in same thread ... blocks and doesn't show a window.  just shows a preview of one in alt+tab...
runnable:run()
thread:showErr()
--]]
-- [[ run on a new Java thread.  same.
local th = J.java.lang.Thread:_new(runnable)
print('thread', th)
th:start()
th:join()
thread:showErr()
--]]
--[[ do invokeLater, but that doesnt block, and I am not Java who waits for all threads to finish ...
--J.javax.swing.SwingUtilities:invokeLater(runnable)
-- does this block until ui quit?
-- no?
J.javax.swing.SwingUtilities:invokeAndWait(runnable)	-- segfaults
thread:showErr()
--]]
