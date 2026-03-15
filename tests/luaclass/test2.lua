#!/usr/bin/env luajit
-- test classes made at runtime
local table = require 'ext.table'
local tolua = require 'ext.tolua'
local J = require 'java'

local JavaLuaClass = require 'java.luaclass'
local TestClass = JavaLuaClass{
	env = J,
	name = 'TestClass',
	fields = {
		{
			name = 'foo',
			sig = 'double',
		}
	},
	methods = {
		{
			name = 'bar',
			value = function(...)
				print("JavaLuaClass TestClass bar() says hello!")
				print('lua got #args', select('#', ...))
				print('lua got args', ...)

				return 3.14
				--return J.Double(3.14)
			end,
			sig = {
				'double',
				--'java.lang.Double',
				'java.lang.Object',
			},
		},
	},
}

print('TestClass', TestClass)
print(tolua(table(TestClass._fields)
	:map(function(x) return {} end) -- table(x, {_env=false}) end)
))
print(tolua(table(TestClass._methods)
	:map(function(x) return {} end) -- table(x, {_env=false}) end)
))
local testObj = TestClass()
print('testObj', testObj)

local obj = testObj:bar( J:_str("testing") )
print('foo returns', obj)
