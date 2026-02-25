#!/usr/bin/env luajit

local thread = require 'thread.lite'{
	code = [=[
	local J = require 'java.vm'{ptr=arg}.jniEnv
	print('J._ptr', J._ptr)	-- changes from the vm's GetEnv call, which wouldn't happen if it was run on the same thread...

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
		local btn1 = JButton'Btn1'
		buttons:add(btn1, gbc)
		local btn2 = JButton'Btn2'
		buttons:add(btn2, gbc)
		local btn3 = JButton'Btn3'
		buttons:add(btn3, gbc)
		local btn4 = JButton'Btn4'
		buttons:add(btn4, gbc)
		-- TODO btn1:addActionListener(listener) -- but then you'd have to make a subclass ...

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
		['java.library.path'] = '.',	-- needed for NativeRunnable
	},
}.jniEnv

local NativeRunnable = require 'java.tests.nativerunnable'(J)	-- build

J.javax.swing.SwingUtilities:invokeAndWait(
	NativeRunnable(thread.funcptr, J._vm._ptr)
)
thread:showErr()
