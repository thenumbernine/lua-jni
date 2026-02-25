#!/usr/bin/env luajit

-- runnable.lua but using Java-ASM instead of an external Runnable subclass
-- (The last hurdle is it still needs some external source to load the Java-ASM bytecode, which at least requires a file-write, or at worse requires a subclass of its own.)

local J = require 'java.vm'{
	props = {
		['java.class.path'] = table.concat({
			'.',
			'asm-9.9.1.jar',
		}, ':'),
	},
}.jniEnv

local NativeRunnable = require 'java.tests.nativerunnable_asm'(J)

callback = function(arg)
	print('hello from within Lua, arg', arg)
end
local ffi = require 'ffi'
closure = ffi.cast('void *(*)(void*)', callback)
NativeRunnable(closure, 1234567):run()
