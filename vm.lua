local ffi = require 'ffi'
require 'java.ffi.jni'		-- get cdefs
local class = require 'ext.class'
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

function JavaVM:init(args)
	args = args or {}

	local options = ffi.new'JavaVMOption[1]'
	options[0].optionString = '-Djava.class.path=.'	-- or path:cwd() ?

	local jvmargs = ffi.new'JavaVMInitArgs'
	jvmargs.version = ffi.C.JNI_VERSION_1_6
	jvmargs.nOptions = 1
	jvmargs.options = options
	jvmargs.ignoreUnrecognized = ffi.C.JNI_FALSE

	local jvm = ffi.new'JavaVM*[1]'
	local jniEnvPtr = ffi.new'JNIEnv*[1]'
	local result = jni.JNI_CreateJavaVM(jvm, jniEnvPtr, jvmargs)
	assert.eq(result, 0, 'JNI_CreateJavaVM')
--DEBUG:print('jvm', jvm[0])
--DEBUG:print('jniEnvPtr', jniEnvPtr[0])

	if jvm[0] == nil then error("failed to find a JavaVM*") end
	self.ptr = jvm[0]
	if jniEnvPtr[0] == nil then error("failed to find a JNIEnv*") end
	self.jniEnv = JNIEnv(jniEnvPtr[0])
end

return JavaVM
