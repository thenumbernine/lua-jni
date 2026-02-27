#!/usr/bin/env luajit

local J = require 'java.vm'{
	props = {
		['java.class.path'] = table.concat({
			'.',
			'asm-9.9.1.jar',		-- needed for ASM
		}, ':'),
		['java.library.path'] = '.',
	},
}.jniEnv

local MakeSAMNativeCallback = require 'java.tests.make_sam_native_callback_asm'
local NativeRunnable = MakeSAMNativeCallback(J, J.Runnable)
NativeRunnable(function(...)
	-- arg is the arguments of the SAM that are captured in an Object[]
	print('hello from within Lua!', ...)
end):run()
