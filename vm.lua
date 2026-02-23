require 'ext.gc'
require 'java.ffi.jni'		-- get cdefs
local ffi = require 'ffi'
local class = require 'ext.class'
local table = require 'ext.table'
local assert = require 'ext.assert'
local io = require 'ext.io'
local JNIEnv = require 'java.jnienv'


local void_ptr_ptr = ffi.typeof'void**'
local char_ptr = ffi.typeof'char*'
local JavaVMOption = ffi.typeof'JavaVMOption'
local JavaVMOption_arr = ffi.typeof'JavaVMOption[?]'
local JavaVMInitArgs = ffi.typeof'JavaVMInitArgs'
local JNIEnv_ptr_1 = ffi.typeof'JNIEnv*[1]'
local JavaVM_ptr = ffi.typeof'JavaVM*'
local JavaVM_ptr_1 = ffi.typeof'JavaVM*[1]'


local JavaVM = class()
JavaVM.__name = 'JavaVM'

JavaVM.version = ffi.C.JNI_VERSION_1_6

--[[
args:
	version optional, defaults to JavaVM.version which defaults to JNI_VERSION_1_6

	ptr = reconstruct our JavaVM object from a JavaVM ffi cdata JNI pointer

	-or- build a new one with...

	optionList = list of option strings
	options = key/value of options to append ${k}=${v}
	props = key/value of props to append -D${k}=${v}
	libjvm = path to libjvm.so. By default it will look in $JAVA_HOME/lib/server/libjvm.so
				... and if $JAVA_HOME is missing, its location will be inferred by "readlink -f `which java`"
--]]
function JavaVM:init(args)
	args = args or {}
	self.version = args.version
	local jniEnvPtrArr = JNIEnv_ptr_1()

	if args.ptr then
		-- reattach to an old JavaVM*
		local jvmPtr = ffi.cast(JavaVM_ptr, args.ptr)
		self._ptr = jvmPtr
		-- assert/assume it is cdata of JavaVM*
		assert.eq(ffi.C.JNI_OK, jvmPtr[0].GetEnv(jvmPtr, ffi.cast(void_ptr_ptr, jniEnvPtrArr), self.version))

		-- if we are creating from an old pointer then we don't want __gc to cleanup so
		function self:destroy() end
	else
		-- create a new JavaVM:

		-- save these separately so lua doesn't gc them
		self.optionStrings = table()
		self.optionTable = table()
		local function addOption(optionStr)
			local str = tostring(optionStr)
			self.optionStrings:insert(str)
			local option = JavaVMOption()
			option.optionString = ffi.cast(char_ptr, str)
			self.optionTable:insert(option)
		end
		if args.optionList then
			for _,option in ipairs(args.optionList) do
				addOption(option)
			end
		end
		if args.options then
			for k,v in pairs(args.options) do
				addOption(k..'='..v)
			end
		end
		if args.props then
			for k,v in pairs(args.props) do
				addOption('-D'..k..'='..v)
			end
		end
		self.options = JavaVMOption_arr(#self.optionTable, self.optionTable)

		local jvmargs = JavaVMInitArgs()
		jvmargs.version = self.version
		jvmargs.nOptions = #self.optionTable
		jvmargs.options = self.options
		jvmargs.ignoreUnrecognized = ffi.C.JNI_FALSE

		-- will this gc and unload dload? or nah, I can make it a local?
		local libjvmpath = args.libjvmpath
			or require 'java.build'.getJavaHome()..'/lib/server/libjvm.so'
		self.jni = ffi.load(libjvmpath)

		local jvmPtrArr = JavaVM_ptr_1()
		local result = self.jni.JNI_CreateJavaVM(jvmPtrArr, jniEnvPtrArr, jvmargs)
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
