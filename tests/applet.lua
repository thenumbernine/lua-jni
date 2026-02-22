#!/usr/bin/env luajit
require 'java.tests.nativerunnable'	-- build

local JVM = require 'java.vm'
local jvm = JVM{
	props = {
		['java.library.path'] = '.',	-- needed for NativeRunnable
	}
}

local LiteThread = require 'thread.lite'
local thread = LiteThread{
	code = [=[
	local J = require 'java.vm'{ptr=arg}.jniEnv
	print('J._ptr', J._ptr)	-- changes from the vm's GetEnv call, which wouldn't happen if it was run on the same thread...

	local JFrame = J.javax.swing.JFrame
	local frame = JFrame:_new'HelloWorldSwing Example'
	frame:setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE)

	local JLabel = J.javax.swing.JLabel
	local label = JLabel:_new'Hello World!'
	frame:add(label)

	frame:setSize(300, 200)				-- you need to call one or the other
	--frame:pack()
	frame:setLocationRelativeTo(nil)	-- puts it in the middle
	frame:setVisible(true)				-- shows it

	print'THREAD DONE'
]=],
}

local J = jvm.jniEnv
J.javax.swing.SwingUtilities:invokeAndWait(
	J.io.github.thenumbernine.NativeRunnable(thread.funcptr, J._vm._ptr)
)
thread:showErr()
