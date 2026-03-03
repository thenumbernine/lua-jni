#!/usr/bin/env luajit
-- make a class from scratch
local assert = require 'ext.assert'
local J = require 'java'

local Test = require 'java.luaclass'{
	env = J,
	name = 'TestStatic',
	fields = {
		{		-- key=seq int, value=table, use as properties for JavaASMClass
			name = 'moo',
			sig = 'java.lang.Class',
		},
		foo = 'long',		-- key=string, value=string, use name=type
		bar = 'java.lang.String',
		baz = {
			isStatic = true,
			value = {tag='long', value='137'},	-- structure used by JavaASMClass
			sig = 'long',
		},
		doo = {				-- key=string value=table, use name for key, and the rest of the value properties
			isStatic = true,
			sig = 'double[]',
		},
		'loo',	-- key=seq int, value=string, use name for value
	},
	methods = {
		-- [[
		toString = function(this)
			return 'from Test.toString()'
		end,
		testFunc = {
			sig = {'double', 'java.lang.String', 'java.lang.Object'},
			value = function(this, ...)
				print('this=', this)
				print('here with', ...)
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
		--[[ hmm adding a static method crashes
		{
			name = 'testStatic',
			isStatic = true,
			sig = {'void'},
			value = function(...)
				print('here with', ...)
			end,
		}
		--]]
	},
}
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

--test:testStatic()
