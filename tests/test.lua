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
			assert.eq(r.srcs[1]:gsub('%.java$', '%.class$'), r.dsts[1])	-- or else find where it will go ...
			os.exec('javac "'..r.srcs[1]..'"')
		end,
	}
	targets:run(dst)
end


local ffi = require 'ffi'
local JVM = require 'java.vm'
local jvm = JVM()			-- setup for classpath=.
local J = jvm.jniEnv
print('JNIEnv', J)
print('JNI version', ('%x'):format(J:_version()))

--public class Test {
local Test = J:_class(classname)
print('Test', Test)
-- J:_class returns a JavaClass wrapper to a jclass pointer
-- so Test._ptr is a ... jobject ... of the class

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
print('new string', J:_str'new string')
print('#(new string)', #J:_str'new string')

-- can I make an array of Strings?
local arr = J:_newArray('java/lang/String', 3)
print('arr String[3]', arr)
print('arr:getClass():getName()', arr:getClass():getName())	-- [Ljava/lang/String; ... i.e. String[]
-- can I get its length?
print('#(arr String[3])', #arr)

arr:_set(0, 'a')
arr:_set(1, 'b')
arr:_set(2, 'c')

print('arr[0]', arr:_get(0))
print('arr[1]', arr:_get(1))
print('arr[2]', arr:_get(2))

local doubleArr = J:_newArray('double', 5)
print('doubleArr', doubleArr)
print('doubleArr.getClass().getName()', 
	doubleArr:getClass():getName()	-- '[D' ... just like the signature
)

doubleArr:_set(3, 3.14)
print('doubleArr[3]', doubleArr:_get(3))

local charArr = J:_newArray('char', 2)
charArr:_set(0, 100)
charArr:_set(1, 101)
--print('charArr[2]', charArr:_get(2))	-- exception
print('charArr[0]', charArr:_get(0))
print('charArr[1]', charArr:_get(1))

jvm:destroy()
