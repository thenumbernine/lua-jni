#!/usr/bin/env luajit

local thread = require 'thread.lite'{
	code = [=[
	local J = require 'java.vm'{ptr=arg}.jniEnv
	print('J._ptr', J._ptr)	-- changes from the vm's GetEnv call, which wouldn't happen if it was run on the same thread...

	-- now that we've built the JavaVM in the new thread,
	--  we can build the new JavaClass objects
	require 'java.tests.nativerunnable_asm'.cache = 
		J:_getClassForJClass(NativeRunnable_ptr)
	require 'java.tests.nativecallback_asm'.cache =
		J:_getClassForJClass(NativeCallback_ptr)

	local JFrame = J.javax.swing.JFrame
	local frame = JFrame'HelloWorldSwing Example'
	frame:setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE)

	do
		local JPanel = J.javax.swing.JPanel
		local panel = JPanel()
		panel:setBorder(J.javax.swing.border.EmptyBorder(10, 10, 10, 10))

		local GridBagLayout = J.java.awt.GridBagLayout
		panel:setLayout(GridBagLayout())

		local GridBagConstraints = J.java.awt.GridBagConstraints
		local gbc = GridBagConstraints ()
		gbc.gridwidth = GridBagConstraints.REMAINDER
		gbc.anchor = GridBagConstraints.NORTH

		local JLabel = J.javax.swing.JLabel
		panel:add(JLabel[[
<html>
	<hr>
	<h1><strong><i>Hello</i></strong></h1>
	<hr>
</html>
]], gbc)

		gbc.anchor = GridBagConstraints.CENTER
		gbc.fill = GridBagConstraints.HORIZONTAL

		local buttons = JPanel(GridBagLayout())

		local JButton = J.javax.swing.JButton
		local NativeActionListener = require 'java.tests.nativeactionlistener_asm'(J)	-- use java-ASM (still needs gcc)

		local ffi = require 'ffi'

		local btn1 = JButton'Btn1'
		btn1:addActionListener(NativeActionListener(
			ffi.cast('void *(*)(void*)', function(arg)
				print('button1 click')
			end), 0
		))
		buttons:add(btn1, gbc)

		local btn2 = JButton'Btn2'
		btn2:addActionListener(NativeActionListener(
			ffi.cast('void *(*)(void*)', function(arg)
					print('button2 click')
			end), 0
		))
		buttons:add(btn2, gbc)

		local btn3 = JButton'Btn3'
		btn3:addActionListener(NativeActionListener(
			ffi.cast('void *(*)(void*)', function(arg)
				print('button3 click')
			end), 0
		))
		buttons:add(btn3, gbc)

		local btn4 = JButton'Btn4'
		btn4:addActionListener(NativeActionListener(
			ffi.cast('void *(*)(void*)', function(arg)
				print('button4 click')
			end), 0
		))
		buttons:add(btn4, gbc)

		gbc.weighty = 1
		panel:add(buttons, gbc)

		frame:add(panel)
	end

	frame:pack()
	frame:setLocationRelativeTo(nil)	-- puts it in the middle
	frame:setVisible(true)				-- shows it

	print'THREAD DONE'
]=],
}

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

-- when using JavaASM to biuld classes dynamically,
-- we can't build the same dynamic class twice in the same JVM,
--  so forward them to the thread sub-lua
-- but we shouldn't build them in the sub-lua yet until we get our VM until we get our new env until the new thread 
-- OR I could just re-grab them by classname in the new thread ...
thread.lua([[
NativeRunnable_ptr = assert(...)
]], require 'java.tests.nativerunnable_asm'.cache._ptr)

thread.lua([[
NativeCallback_ptr = assert(...)
]], require 'java.tests.nativecallback_asm'.cache._ptr)

J.javax.swing.SwingUtilities:invokeAndWait(
	NativeRunnable(thread.funcptr, J._vm._ptr)
)
thread:showErr()
