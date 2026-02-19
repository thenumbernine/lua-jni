require 'ext.gc'
require 'java.ffi.jni'		-- get cdefs
local ffi = require 'ffi'
local class = require 'ext.class'
local table = require 'ext.table'
local assert = require 'ext.assert'
local io = require 'ext.io'
local JNIEnv = require 'java.jnienv'


local javaHome = require 'java.build'.javaHome
local jni = ffi.load(javaHome..'/lib/server/libjvm.so')


local JavaVM = class()
JavaVM.__name = 'JavaVM'

--[[
args:
	version, defaults to JNI_VERSION_1_6

	ptr = reconstruct our JavaVM object from a JavaVM ffi cdata JNI pointer

	-or- build a new one with...

	props = key/value of props to set with -D
--]]
function JavaVM:init(args)
	args = args or {}
	local version = args.version or ffi.C.JNI_VERSION_1_6
	local jniEnvPtrArr = ffi.new'JNIEnv*[1]'

	if args.ptr then
		-- reattach to an old JavaVM*
		local jvmPtr = ffi.cast('JavaVM*', args.ptr)
		self._ptr = jvmPtr
		-- assert/assume it is cdata of JavaVM*
		assert.eq(ffi.C.JNI_OK, jvmPtr[0].GetEnv(jvmPtr, ffi.cast('void**', jniEnvPtrArr), version))

		-- if we are creating from an old pointer then we don't want __gc to cleanup so
		function self:destroy() end
	else
		-- create a new JavaVM:

		-- save these separately so lua doesn't gc them
		self.optionStrings = table()
		self.optionTable = table()
		if args.props then
			for k,v in pairs(args.props) do
				local str = '-D'..k..'='..v
				self.optionStrings:insert(str)
				local option = ffi.new'JavaVMOption'
				option.optionString = ffi.cast('char*', str)
				self.optionTable:insert(option)
			end
		end
		self.options = ffi.new('JavaVMOption[?]', #self.optionTable, self.optionTable)

		local jvmargs = ffi.new'JavaVMInitArgs'
		jvmargs.version = version
		jvmargs.nOptions = #self.optionTable
		jvmargs.options = self.options
		jvmargs.ignoreUnrecognized = ffi.C.JNI_FALSE

		local jvmPtrArr = ffi.new'JavaVM*[1]'
		local result = jni.JNI_CreateJavaVM(jvmPtrArr, jniEnvPtrArr, jvmargs)
		assert.eq(result, 0, 'JNI_CreateJavaVM')

		if jvmPtrArr[0] == nil then error("failed to find a JavaVM*") end
		self._ptr = jvmPtrArr[0]
	end

	if jniEnvPtrArr[0] == nil then error("failed to find a JNIEnv*") end
	self.jniEnv = JNIEnv{
		vm = self,
		ptr = jniEnvPtrArr[0],
	}

	-- no longer need to retain for gc
	self.options = nil
	self.optionTable = nil
	self.optionStrings = nil
end

function JavaVM:destroy()
	if self._ptr then
		-- do you need to destroy the JNIEnv?
		local result = self._ptr[0].DestroyJavaVM(self._ptr)
		if result ~= 0 then
			print('DestroyJavaVM failed with code', result)
		end
		self._ptr = nil
	end
end

function JavaVM:__gc()
	self:destroy()
end

return JavaVM
