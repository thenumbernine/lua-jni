#!/usr/bin/env luajit
--[[
test classes made at runtime
--]]
local table = require 'ext.table'
local tolua = require 'ext.tolua'
local J = require 'java.vm'{
	props = {
		['java.class.path'] = table.concat({
			'.',
			'asm-9.9.1.jar',		-- needed for ASM
		}, ':'),
		['java.library.path'] = '.',
	},
}.jniEnv

local LuaJavaClass = require 'java.tests.lua_java_class'
local TestClass = LuaJavaClass{
	env = J,
	--name = 'TestClass',	-- JVM java.lang.IllegalArgumentException: TestClass not in same package as lookup class
	name = 'io.github.thenumbernine.TestClass',	-- works
	fields = {
		{
			name = 'foo',
			sig = 'double',
		}
	},
	methods = {
		{
			name = 'bar',
			func = function(...)
				print("Foo says hello!")
				print('args', ...)

				return 3.14
				--return J.Double(3.14)
			end,
			sig = {
				'double',--'java.lang.Double',
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
print(tolua(table(TestClass._ctors)
	:map(function(x) return {} end) -- table(x, {_env=false}) end)
))
local testObj = TestClass()
print('testObj', testObj)

local obj = testObj:bar( J:_str("testing") )
print('foo returns', obj)
