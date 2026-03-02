#!/usr/bin/env luajit
-- needs to be run in java/tests/asmclass/

local J = require 'java'

local NativeRunnable = require 'java.tests.asmclass.nativerunnable_asmclass'(J)	-- "WE'LL DO IT LIVE!!!!"

local ffi = require 'ffi'
callback = function(arg)
	arg = J:_javaToLuaArg(arg, 'java.lang.Long')
	print('hello from within Lua, arg', arg)
end
closure = ffi.cast('void *(*)(void*)', callback)
NativeRunnable(
	closure,
	J.Long:valueOf(123456789)
):run()
