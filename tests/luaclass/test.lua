#!/usr/bin/env luajit
-- make a class from scratch
local assert = require 'ext.assert'
local J = require 'java'

local Test = J.Object:_subclass{
	name = 'Test',
	fields = {
		{		-- key=seq int, value=table, use as properties for JavaASMClass
			name = 'moo',
			sig = 'java.lang.Class',
		},
		foo = 'long',		-- key=string, value=string, use name=type
		bar = 'java.lang.String',
		baz = {
			isStatic = true,
			isPublic = true,
			-- NOTICE I am initializing values as field's ConstantValue attribute
			-- but it looks like javac initializes values as <clinit> assignment
			value = {tag='long', value=137},	-- structure used by JavaASMClass
			sig = 'long',
		},
		doo = {				-- key=string value=table, use name for key, and the rest of the value properties
			isStatic = true,
			isPublic = true,
			sig = 'double[]',
		},
		'loo',	-- key=seq int, value=string, use name for value

		{
			name = 'privateVar',
			sig = 'int',
			isPrivate = true,
		},
	},
	ctors = {
		function(this)
			print"in custom ctor #1!"
		end,
		{
			isPublic = true,
			sig = {'void', 'double'},
			value = function(this, x)
				print("in custom ctor #2 with double", x)
			end,
		},
	},
	methods = {
		-- [[
		toString = function(this)
			return 'from Test.toString()'
		end,
-- [=[
		testFunc = {
			isPublic = true,
			sig = {'double', 'java.lang.String', 'java.lang.Object'},
			value = function(this, ...)
				print('this', this)
				print('in Test.testFunc with args:', ...)
				return 42
			end,
		},
		--]]
		--[[ same same but verbose
		{
			isPublic = true,
			name = 'toString',
			sig = {'java.lang.String'},
			value = function(this)
				return 'from Test.toString()'
			end,
		}
		--]]
		-- [[
		{
			name = 'testStatic',
			isStatic = true,
			isPublic = true,
			sig = {'void', 'double'},
			value = function(...)
				print('in static Test.testStatic with args:', ...)
			end,
		},
		--]]
		{
			name = 'testBool',
			isPublic = true,
			sig = {'java.lang.String', 'boolean'},
			value = function(this, b)
				return b and 'yes' or 'no'
			end,
		},
		{
			name = 'testInt',
			isPublic = true,
			sig = {'java.lang.String', 'int'},
			value = function(this, b)
print('in testInt with', b)
				return bit.band(b, 1) == 1 and 'odd' or 'even'
			end,
		},

		{
			name = 'testNewLuaState',
			isPublic = true,
			sig = {'java.lang.String'},
			newLuaState = true,
			value = function(J, this)
				return J:_str'testing!'
			end,
		},
--]=]
	},
}
print(Test.__name)
print('Test', Test)

local test = Test()
print('test', test)

assert.eq(test.foo, 0LL)
test.foo = -1
assert.eq(test.foo, -1LL)

print('test.bar', test.bar)
assert.eq(test.bar, nil)

test.bar = 'bar'
assert.eq(tostring(test.bar), 'bar')
print('test.bar', test.bar)

assert.eq(test.doo, nil)
print('test.doo', test.doo)
test.doo = J:_newArray('double', 10)
print('test.doo', test.doo)
assert.len(test.doo, 10)
print('#test.doo', #test.doo)
assert.eq(test.doo[3], 0)
test.doo[3] = math.pi
assert.eq(test.doo[3], math.pi)

local test2 = Test()
print('test2.doo', test2.doo)
assert.eq(test2.doo, test.doo)	-- make sure static field is shared between objects

-- make sure our initialized static long field works
assert.eq(test.baz, 137LL)
assert.eq(test2.baz, 137LL)
print('test.baz', test.baz)

print('test:testFunc()', assert.eq(test:testFunc("", "testing"), 42))

Test(2)

test:testStatic(math.pi)

assert.eq(tostring(test:testNewLuaState()), 'testing!')


local Test2 = Test:_subclass{
	methods = {
		testFunc = {
			isPublic = true,
			sig = {'double', 'java.lang.String'},
			value = function(this, s)
print('this', this)
print('this.super', this.super)
				return 1+this.super:testFunc("test", J.Object())
			end,
		},
	},
}
print('Test2.super', Test2.super)
print('Test2.super == Test', Test2.super == Test)
local test2 = Test2()
print('test2.super', test2.super)
print('test2.baz', test2.baz)
print('test2.testFunc', test2:testFunc('here'))

print('test2 from ptr', J:_fromJObject(test2._ptr))
print("test2 from ptr's super", J:_fromJObject(test2._ptr).super)

assert.eq(tostring(test2:testBool(true)), "yes")
assert.eq(tostring(test2:testBool(false)), "no")
assert.eq(tostring(test2:testBool(J.Boolean(true))), "yes")
assert.eq(tostring(test2:testBool(J.Boolean(false))), "no")

assert.eq(tostring(test2:testInt(3)), "odd")
assert.eq(tostring(test2:testInt(4)), "even")
assert.eq(tostring(test2:testInt(J.Integer(5))), "odd")
assert.eq(tostring(test2:testInt(J.Integer(6))), "even")

local Test3 = Test2:_subclass{
	methods = {
		{
			name = 'testBool',
			isPublic = true,
			sig = {'java.lang.String', 'boolean'},
			value = function(this, b)
				return b and 'YES' or 'NO'
			end,
		},
	},
}
local test3 = Test3()
assert.eq(tostring(test3:testBool(true)), "YES")
assert.eq(tostring(test3:testBool(false)), "NO")
assert.eq(tostring(test3:testBool(J.Boolean(true))), "YES")
assert.eq(tostring(test3:testBool(J.Boolean(false))), "NO")
assert.eq(tostring(test3.super:testBool(true)), "yes")
assert.eq(tostring(test3.super:testBool(false)), "no")
assert.eq(tostring(test3.super:testBool(J.Boolean(true))), "yes")
assert.eq(tostring(test3.super:testBool(J.Boolean(false))), "no")

print'DONE'
