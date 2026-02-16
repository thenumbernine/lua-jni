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
print('jniEnv', jniEnv)

--public class Test {
local Test = jniEnv:findClass(classname)
print('Test', Test)
-- jniEnv:findClass returns a JavaClass wrapper to a jclass pointer
-- so Test.ptr is a ... jobject ... of the class

print('Test:getName()', Test:getName())
-- TODO how to get some name other than "java.lang.Class" ?
-- TODO how to enumerate all properties of a JavaClass?
--]]

--public static String test() { return "Testing"; }
-- TODO is there a way to get a method signature?
local Test_test = Test:getMethod{name='test', sig={'java.lang.String'}, static=true}
print('Test.test', Test_test)

local result = Test_test(Test)
print('Test.test()', result)
