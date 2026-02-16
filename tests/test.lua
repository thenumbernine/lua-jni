#!/usr/bin/env luajit
-- following https://www.inonit.com/cygwin/jni/invocationApi/c.html
local os = require 'ext.os'
os.exec'javac Test.java'

local ffi = require 'ffi'
local JVM = require 'java.vm'
local jvm = JVM()
local jniEnv = jvm.jniEnv
print(jniEnv)

--public class Test {
local Test = jniEnv:findClass'Test'
print('Test', Test)

--public static String test() { return "Testing"; }
local Test_test = Test:getStaticMethod('test', '()Ljava/lang/String;')
print('Test.test', Test_test)

local result = Test_test()
print('result', result)
-- and that's a jobject, which is a void*
-- to get its string contents ...
local str = jniEnv.ptr[0].GetStringUTFChars(jniEnv.ptr, result, nil)
local luastr = str ~= nil and ffi.string(str) or nil
jniEnv.ptr[0].ReleaseStringUTFChars(jniEnv.ptr, result, str)
print('result', luastr)
