#!/usr/bin/env luajit
-- just run a bunch of stuff and see if anything crashes
local assert = require 'ext.assert'

require 'make.targets'():add{	-- make sure it's built
	dsts = {'Test.class'},
	srcs = {'Test.java'},
	rule = function(r)
		assert.eq(r.srcs[1]:gsub('%.java$', '%.class'), r.dsts[1])	-- or else find where it will go ...
		assert(require 'ext.os'.exec('javac "'..r.srcs[1]..'"'))
	end,
}:runAll()

local ffi = require 'ffi'
local J = require 'java'
print('JNIEnv', J)
print('JNI version', ('%x'):format(J:_version()))

print('java.lang.Class', J:_findClass'java.lang.Class')
print('java.lang.String', J:_findClass'java.lang.String')

--public class Test {
local Test = J:_findClass'Test'
print("Test from J:_findClass'Test'", Test)
-- J:_findClass returns a JavaClass wrapper to a jclass pointer
-- so Test._ptr is a ... jobject ... of the class
local Test2 = J.Test			-- runtime namespace resolution (slow but concise)
print('Test from J.Test', Test2)
assert.eq(Test, Test2)

print('Test:_name()', Test:_name())
-- TODO how to get some name other than "java.lang.Class" ?
-- TODO how to enumerate all properties of a JavaClass?


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

local testObj = Test:_new()
print('testObj', testObj)


-- test J:_new(classpath, args)
-- test J:_new(classobj, args)
-- test classobj:_new(args)

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

print('testObj:test()', testObj:test())

print('Test:test()', Test:test())

print('Test:_super()', Test:_super())

-- can I make a new String?
-- chicken-and-egg, you have to use JNIEnv
local s = J:_str'new string'
print('new string', s)
print('#(new string)', #s)
print('new string class', s:_getClass())
print('new string class', s:_getClass():_getDebugStr())
print('new string class', s:_getClass():_name())

print('J', J)
print('J.java', J.java)
print('J.java.lang', J.java.lang)
local String = J.java.lang.String
print('java.lang.String', String)

-- can I make an array of Strings?
local arr = J:_newArray('java.lang.String', 3)
print('arr String[3]', arr)
print('arr:_getClass():_name()', arr:_getClass():_name())	-- [Ljava/lang/String; ... i.e. String[]
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
print('doubleArr:_getClass()', doubleArr:_getClass())	-- wait, this returns "char[]", probably because that was given to jniEnv to create the array
print('doubleArr._getClass()._name()', doubleArr:_getClass():_name())	-- "double[]"
print('doubleArr:_getClass():_super()', doubleArr:_getClass():_super())
print('doubleArr:_super()', doubleArr:_super())

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

print('charArr.length', charArr.length)
print('charArr:_getClass()._members.length', charArr:_getClass()._members.length)
print('charArr:_getClass()', charArr:_getClass())	-- wait, this returns "char[]", probably because that was given to jniEnv to create the array
print('charArr:_getClass():_name()', charArr:_getClass():_name())
print('charArr:_getClass():_super()', charArr:_getClass():_super())
--print('J.java.lang.Array', J.java.lang.Array)

print'DONE'
