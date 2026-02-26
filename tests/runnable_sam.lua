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

local ffi = require 'ffi'
local assert = require 'ext.assert'
local SAMRunnable = MakeSAMNativeCallback(J, J.Runnable)
rawset(SAMRunnable, '_cb', function(self, callback)
	assert.type(callback, 'function')
	
	local closure = ffi.cast('void *(*)(void*)', callback)
	local obj = self:_new(
		ffi.cast('jlong', closure)
	)
	
	rawset(obj, '_callbackDontGC', callback)
	rawset(obj, '_callbackClosure', closure)

	-- TODO override obj __gc to free closure
	local mt = getmetatable(obj)
	-- assert each object gets their own mt ...
	assert.ne(mt, SAMRunnable)
	local oldgc = mt.__gc
	mt.__gc = function(self)
		local closure = rawget(self, '_callbackClosure')
		if closure then closure:free() end
		rawset(self, '_callbackClosure', nil)
		rawset(self, '_callbackDontGC', nil)
		if oldgc then oldgc(self) end
	end

	return obj
end)


--local NativeRunnable = require 'java.tests.nativerunnable_asm'(J)	-- use java-ASM (still needs gcc)

SAMRunnable:_cb(function(arg)
	-- arg is the arguments of the SAM that are captured in an Object[]
	arg = J:_javaToLuaArg(arg, 'java.lang.Object[]')
	print('hello from within Lua!') 
end):run()
