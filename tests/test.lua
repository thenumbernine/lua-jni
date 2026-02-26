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

print('java.lang.Object', J:_findClass'java.lang.Object')
print('java.lang.Class', J:_findClass'java.lang.Class')

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
local Test_test = assert(Test:_method{name='test', sig={'java.lang.String'}, isStatic=true})
print('Test.test', Test_test)
print('Test.test()', Test_test(Test))

-- try to make a new Test()
local Test_init = assert(Test:_method{name='<init>', sig={}})
print('Test_init', Test_init)
local testObj = Test_init:_new(Test)
print('testObj', testObj)

local testObj = Test:_new()
print('testObj', testObj)

-- overload from Lua types
print'from lua prims'
print('testObj:ol(true)', testObj:ol(true))							-- correct
print('testObj:ol(1)', testObj:ol(1))
print('testObj:ol("foo")', testObj:ol('foo'))						-- correct

-- overload from ctypes
print'from ffi prims'
print('testObj:ol(J.boolean())', testObj:ol(J.boolean()))					-- correct
print('testObj:ol((short)1)', testObj:ol(J.short(1)))						-- correct
print('testObj:ol((int)1)', testObj:ol(J.int(1)))							-- correct
print('testObj:ol((float)1)', testObj:ol(J.float(1)))						-- correct
print('testObj:ol((double)1)', testObj:ol(J.double(1)))						-- correct
print('testObj:ol((long)1)', testObj:ol(J.long(1)))							-- correct

-- overload of boxed types ... when reslver has prim or Object it will choose Object ..
print'from boxed prims'
print('testObj:ol(new Boolean(true))', testObj:ol(J.Boolean:_new(true)))		-- RIGHT - Object
print('testObj:ol(new Short(1))', testObj:ol(J.Short:_new(1)))				-- RIGHT - Object
print('testObj:ol(new Int(1))', testObj:ol(J.Integer:_new(1)))				-- RIGHT - Object
print('testObj:ol(new Float(1))', testObj:ol(J.Float:_new(1)))				-- WRONG - float
print('testObj:ol(new Double(1))', testObj:ol(J.Double:_new(1)))				-- WRONG - double
print('testObj:ol(new Long(1))', testObj:ol(J.Long:_new(1)))					-- RIGHT - Object

-- overload from objects
print'from objects'
print('testObj:ol(String("foo"))', testObj:ol(J:_str'foo'))					-- correct
print('testObj:ol(Object())', testObj:ol( J.Object:_new() ))		-- correct

-- overload from arrays
print'from arrays'
print('testObj:ol(char[]{})', testObj:ol( J:_newArray('char', 1) ))			-- TODO this matches to Object, not prim-of-array

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

print('testObj instanceof Object', testObj:_instanceof(J.Object))
local testObjAsObject = testObj:_cast(J.Object)
print('(Object)testObj', testObjAsObject)
local testObjAsObjectAsTest = testObjAsObject:_cast(Test)
print('(Test)(Object)testObj', testObjAsObjectAsTest)

print'DONE'
