#!/usr/bin/env luajit

local thread = require 'thread.lite'{
	code = [=[
	local J = require 'java.vm'{ptr=jvmPtr}.jniEnv
	print('J._ptr', J._ptr)	-- changes from the vm's GetEnv call, which wouldn't happen if it was run on the same thread...

	-- init the cache from the already-generated classes
	-- because generating them twice will cause an error.
	require 'java.tests.nativerunnable_asm'.cache = 
		J:_findClass'io.github.thenumbernine.NativeRunnable'
	require 'java.tests.nativecallback_asm'.cache =
		J:_findClass'io.github.thenumbernine.NativeCallback'
	local NativeActionListener = J:_findClass'io.github.thenumbernine.NativeActionListener'
	require 'java.tests.nativeactionlistener_asm'.cache = NativeActionListener 

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

		local ffi = require 'ffi'

		local btn1 = JButton'Btn1'
		btn1:addActionListener(NativeActionListener(
			ffi.cast('void *(*)(void*)', function(arg)
				arg = J:_javaToLuaArg(arg, 'java.awt.event.ActionListener')
				print('button1 click', arg)
			end)
		))
		buttons:add(btn1, gbc)

		local btn2 = JButton'Btn2'
		btn2:addActionListener(NativeActionListener(
			ffi.cast('void *(*)(void*)', function(arg)
				arg = J:_javaToLuaArg(arg, 'java.awt.event.ActionListener')
				print('button2 click', arg)
			end)
		))
		buttons:add(btn2, gbc)

		local btn3 = JButton'Btn3'
		btn3:addActionListener(NativeActionListener(
			ffi.cast('void *(*)(void*)', function(arg)
				arg = J:_javaToLuaArg(arg, 'java.awt.event.ActionListener')
				print('button3 click', arg)
			end)
		))
		buttons:add(btn3, gbc)

		local btn4 = JButton'Btn4'
		btn4:addActionListener(NativeActionListener(
			ffi.cast('void *(*)(void*)', function(arg)
				arg = J:_javaToLuaArg(arg, 'java.awt.event.ActionListener')
				print('button4 click', arg)
			end)
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
		['java.library.path'] = '.',
	},
}.jniEnv

--local NativeRunnable = require 'java.tests.nativerunnable'(J)		-- use javac and gcc
local NativeRunnable = require 'java.tests.nativerunnable_asm'(J)	-- use java-ASM (still needs gcc)
local NativeActionListener = require 'java.tests.nativeactionlistener_asm'(J)	-- use java-ASM (still needs gcc)

local ffi = require 'ffi'
thread.lua([[ jvmPtr = ... ]], ffi.cast('uint64_t', J._vm._ptr))

J.javax.swing.SwingUtilities:invokeAndWait(
	NativeRunnable(thread.funcptr)
)
thread:showErr()
