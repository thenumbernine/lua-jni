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

--[[ using a root name native class:
require 'java.build'.C{
	src = 'DynamicNativeRunnable.c',
	dst = 'libDynamicNativeRunnable.so',
}
local newClassName = 'NativeRunnable'
--]]
-- [[ using my io.github namespace:
local newClassName = 'io/github/thenumbernine/NativeRunnable'
local NativeRunnable_classObj = require 'java.tests.nativerunnable_asm'(J)
local NativeRunnable = J:_getClassForJClass(NativeRunnable_classObj._ptr)
--]]

callback = function(arg)
	print('hello from within Lua, arg', arg)
end
local ffi = require 'ffi'
closure = ffi.cast('void *(*)(void*)', callback)
local nativeRunnable = NativeRunnable(
	ffi.cast(J.long, closure),
	ffi.cast(J.long, 1234567)
)
nativeRunnable:run()
