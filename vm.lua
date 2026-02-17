require 'ext.gc'
require 'java.ffi.jni'		-- get cdefs
local ffi = require 'ffi'
local class = require 'ext.class'
local table = require 'ext.table'
local assert = require 'ext.assert'
local io = require 'ext.io'
local path = require 'ext.path'
local JNIEnv = require 'java.jnienv'


-- how to know which jvm to load?
-- this needs to be done only once per app, where to do it?
local javalinkpath = io.readproc'which java'
local javaBinaryPath = io.readproc('readlink -f '..javalinkpath)
--DEBUG:print('javaBinaryPath', javaBinaryPath)
local javabindir = path(javaBinaryPath):getdir()	-- java ... /bin/
local javarootdir = javabindir:getdir()				-- java ...
local jni = ffi.load((javarootdir/'lib/server/libjvm.so').path)


local JavaVM = class()
JavaVM.__name = 'JavaVM'

--[[
args:
	version
	classpath
--]]
function JavaVM:init(args)
	args = args or {}

	local optionTable = table()
	if args.classpath then
		local option = ffi.new'JavaVMOption'
		option.optionString = '-Djava.class.path='..args.classpath
		optionTable:insert(option)
	end
	local options = ffi.new('JavaVMOption[?]', #optionTable, optionTable)

	local jvmargs = ffi.new'JavaVMInitArgs'
	jvmargs.version = args.version or ffi.C.JNI_VERSION_1_6
	jvmargs.nOptions = #optionTable
	jvmargs.options = options
	jvmargs.ignoreUnrecognized = ffi.C.JNI_FALSE

	local jvm = ffi.new'JavaVM*[1]'
	local jniEnvPtr = ffi.new'JNIEnv*[1]'
	local result = jni.JNI_CreateJavaVM(jvm, jniEnvPtr, jvmargs)
	assert.eq(result, 0, 'JNI_CreateJavaVM')
--DEBUG:print('jvm', jvm[0])
--DEBUG:print('jniEnvPtr', jniEnvPtr[0])

	if jvm[0] == nil then error("failed to find a JavaVM*") end
	self._ptr = jvm[0]
	if jniEnvPtr[0] == nil then error("failed to find a JNIEnv*") end
	self.jniEnv = JNIEnv(jniEnvPtr[0])
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
