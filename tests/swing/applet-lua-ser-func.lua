#!/usr/bin/env luajit
--[[
attempting to use function-serialization instead of inline-strings ...
--]]

local LiteThread = require 'thread.lite'

-- as soon as I move this to an inline function, the style init changes...
local function threadRun(J, this, ...)	-- DO NOT read anything outside this thread from inside this thread.  it will cross thread Lua-state lines.  and then something will break.
	print('threadRun', J, this, ...)

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

		local ActionListener = J.java.awt.event.ActionListener

		local btn1 = JButton'Btn1'
		btn1:addActionListener(ActionListener(function(...)
			print('button1 click', ...)
		end))
		buttons:add(btn1, gbc)

		local btn2 = JButton'Btn2'
		btn2:addActionListener(ActionListener(function(...)
			print('button2 click', ...)
		end))
		buttons:add(btn2, gbc)

		local btn3 = JButton'Btn3'
		btn3:addActionListener(ActionListener(function(...)
			print('button3 click', ...)
		end))
		buttons:add(btn3, gbc)

		local btn4 = JButton'Btn4'
		btn4:addActionListener(ActionListener(function(...)
			print('button4 click', ...)
		end))
		buttons:add(btn4, gbc)

		gbc.weighty = 1
		panel:add(buttons, gbc)

		frame:add(panel)
	end

	frame:pack()
	frame:setLocationRelativeTo(nil)	-- puts it in the middle
	frame:setVisible(true)				-- shows it

	print'THREAD DONE'
end

-- if I make the thread *after* initializing the VM ... segfault
local thread = LiteThread{
	code = [=[
	-- This changes from the vm's GetEnv call, which wouldn't happen if it was run on the same thread...
	local J = require 'java.vm'{ptr=jvmPtr}.jniEnv
	local jarg = J:_fromJObject(arg)
	local javaCallback = assert(load(javaCallbackBC))
	javaCallback(J, jarg:_unpack())
]=],
}

local J = require 'java'

local function CreateThread(args)
	local env = args.env
	local func = args.func
	args.func = nil


	local ffi = require 'ffi'
	thread.lua([[ jvmPtr = ... ]], ffi.cast('uint64_t', env._vm._ptr))
	thread.lua([[ javaCallbackBC = ... ]], string.dump(func))

	local obj = env.Runnable:_cb(thread.funcptr)

	-- TODO need to save this externally
	-- don't let it GC
	-- Java will throw away the Lua object
	 --rawset(obj, '_thread', thread)
	_G.javaLiteThread = thread

	-- on __gc?
	thread:showErr()

	return obj
end

J.javax.swing.SwingUtilities:invokeAndWait(
	CreateThread{
		env = J,
		func = threadRun,
	}
)

