#!/usr/bin/env luajit
-- following https://www.inonit.com/cygwin/jni/invocationApi/c.html

local classname = 'Test'	-- i.e. Test.class, from Test.java

do -- make sure it's built
	local os = require 'ext.os'
	local Targets = require 'make.targets'
	local targets = Targets()
	local dst = classname..'.class'
	local src = 'Test.java'
	targets:add{
		dsts = {dst},
		srcs = {src},
		rule = function(r)
			os.exec('javac "'..r.srcs[1]..'" "'..r.dsts[1]..'"')
		end,
	}
	targets:run(dst)
end


local ffi = require 'ffi'
local JVM = require 'java.vm'
local jvm = JVM()			-- setup for classpath=.
local jniEnv = jvm.jniEnv
print(jniEnv)

--public class Test {
local Test = jniEnv:findClass(classname)
print('Test', Test)
-- jniEnv:findClass returns a JavaClass wrapper to a jclass pointer
-- so Test.ptr is a ... jobject ... of the class

-- ok here's where Java gets stupid.
-- lemme guess, 'Test' before mightve been a class, but it was a Java-object of a class, right?
-- and this is the Java-class of the object of the class?
local Test_class = jniEnv:getObjectClass(Test)
print('Test_class', Test_class)	
-- wait, is this just java.lang.Class or something?
-- yes, yes it is

-- [[ TODO how to enumerate all properties of a JavaClass?
local Test_class_getName = Test_class:getMethod{name='getName', sig={'java.lang.String'}}
print('Test_class_getName', Test_class_getName)
print('Test_class_getName()', Test_class_getName(Test_class))
do return end
--]]

--public static String test() { return "Testing"; }
-- TODO is there a way to get a method signature?
local Test_test = Test:getMethod{name='test', sig={'java.lang.String'}, static=true}
print('Test.test', Test_test)

local result = Test_test()
print('result', result)
-- and that's a jobject, which is a void*
-- to get its string contents ...
local str = jniEnv.ptr[0].GetStringUTFChars(jniEnv.ptr, result, nil)
local luastr = str ~= nil and ffi.string(str) or nil
jniEnv.ptr[0].ReleaseStringUTFChars(jniEnv.ptr, result, str)
print('result', luastr)
