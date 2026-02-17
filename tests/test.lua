#!/usr/bin/env luajit
-- following https://www.inonit.com/cygwin/jni/invocationApi/c.html
local assert = require 'ext.assert'

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
			assert.eq(r.srcs[1]:gsub('%.java$', '%.class'), r.dsts[1])	-- or else find where it will go ...
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

print('java.lang.Class', J:_class'java.lang.Class')
print('java.lang.String', J:_class'java.lang.String')

--public class Test {
local Test = J:_class(classname)	-- fast but verbose way
print("Test from J:_class'Test'", Test)
-- J:_class returns a JavaClass wrapper to a jclass pointer
-- so Test._ptr is a ... jobject ... of the class
local Test2 = J.Test			-- runtime namespace resolution (slow but concise)
print('Test from J.Test', Test2)
assert.eq(Test, Test2)

print('Test:_name()', Test:_name())
-- TODO how to get some name other than "java.lang.Class" ?
-- TODO how to enumerate all properties of a JavaClass?
--]]

--public static String test() { return "Testing"; }
-- TODO is there a way to get a method signature?
local Test_test = assert(Test:_method{name='test', sig={'java.lang.String'}, static=true})
print('Test.test', Test_test)
print('Test.test()', Test_test(Test))

-- try to make a new Test()
local Test_init = assert(Test:_method{name='<init>', sig={}})
print('Test_init', Test_init)
local testObj = Test_init:_new(Test)
print('testObj', testObj)

-- TODO again with jni shorthand ... needs runtime name lookup / function signature matching
--local testObj = J:_new(Test)
-- TODO again with jni shorthand ... needs runtime name lookup / function signature matching
--local testObj = Test:_new()

-- call its java testObj.toString()
print('testObj toString', testObj:_javaToString())

local Test_foo = assert(Test:_field{name='foo', sig='java.lang.String'})
print('Test_foo', Test_foo)
print('testObj.foo', Test_foo(testObj))

local Test_bar = Test:_field{name='bar', sig='int'}
print('testObj.bar', Test_bar(testObj))
Test_bar(testObj, 42)
print('testObj.bar', Test_bar(testObj))

local Test_baz = Test:_field{name='baz', sig='double'}
print('testObj.baz', Test_baz(testObj))
Test_baz(testObj, 234)
print('testObj.baz', Test_baz(testObj))

-- now using inferred read/write
print('testObj.foo', testObj.foo)
print('testObj.bar', testObj.bar)
print('testObj.baz', testObj.baz)

--[[ errors for now, I should try to assign it with Java somehow, idk
testObj.foo = 12345
print('testObj.foo', testObj.foo, type(testObj.foo))
--]]
testObj.foo = 'string'
print('testObj.foo', testObj.foo, type(testObj.foo))

print('testObj.testing()', testObj:test())

-- can I make a new String?
-- chicken-and-egg, you have to use JNIEnv
local s = J:_str'new string'
print('new string', s)
print('#(new string)', #s)
print('new string class', s:_class())
print('new string class', s:_class():_getDebugStr())
print('new string class', s:_class():_name())

print('J', J)
print('J.java', J.java)
print('J.java.lang', J.java.lang)
local String = J.java.lang.String
print('java.lang.String', String)

-- can I make an array of Strings?
local arr = J:_newArray('java.lang.String', 3)
print('arr String[3]', arr)
print('arr:_class():_name()', arr:_class():_name())	-- [Ljava/lang/String; ... i.e. String[]
-- can I get its length?
print('#(arr String[3])', #arr)

arr:_set(0, 'a')
arr:_set(1, 'b')
arr:_set(2, 'c')

print('arr[0]', arr:_get(0))
print('arr[1]', arr:_get(1))
print('arr[2]', arr:_get(2))
arr[1] = J:_str'testing'
print('arr[0]', arr[0])
print('arr[1]', arr[1])
print('arr[2]', arr[2])

local doubleArr = J:_newArray('double', 5)
print('doubleArr', doubleArr)
print('doubleArr._class()._name()',
	doubleArr:_class():_name()	-- '[D' ... just like the signature
)

doubleArr:_set(3, 3.14)
print('doubleArr[3]', doubleArr:_get(3))

local charArr = J:_newArray('char', 2)
charArr:_set(0, 100)
charArr:_set(1, 101)
--print('charArr[2]', charArr:_get(2))	-- exception
print('charArr[0]', charArr:_get(0))
print('charArr[1]', charArr:_get(1))
print('charArr[0]', charArr[0])
print('charArr[1]', charArr[1])

jvm:destroy()
