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
local Test_test = Test:getMethod{name='test', sig={'java/lang/String'}, static=true}
print('Test.test', Test_test)
print('Test.test()', Test_test(Test))

-- try to make a new Test()
local Test_init = Test:getMethod{name='<init>', sig={}}
print('Test_init', Test_init)


-- call its tostring
local testObj = Test_init:newObject(Test)
print('testObj', testObj)

print('testObj toString', testObj:getJavaToString())

-- can I make a new String?
-- chicken-and-egg, you have to use JNIEnv
print('new string', jniEnv:newStr'new string')
print('#(new string)', #jniEnv:newStr'new string')

-- can I make an array of Strings?
local arr = jniEnv:newArray('java/lang/String', 3)
print('arr String[3]', arr)
print('arr:getClass():getName()', arr:getClass():getName())	-- [Ljava/lang/String; ... i.e. String[]
-- can I get its length?
print('#(arr String[3])', #arr)

arr:setElem(0, jniEnv:newStr'a')
arr:setElem(1, jniEnv:newStr'b')
arr:setElem(2, jniEnv:newStr'c')

print('arr[0]', arr:getElem(0))
print('arr[1]', arr:getElem(1))
print('arr[2]', arr:getElem(2))

local doubleArr = jniEnv:newArray('double', 5)
print('doubleArr', doubleArr)
print('doubleArr.getClass().getName()', 
	doubleArr:getClass():getName()	-- '[D' ... just like the signature
)
