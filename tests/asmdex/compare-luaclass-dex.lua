#!/usr/bin/env luajit
--[[
build something in dex
compare it to JavaASMDex
--]]
local string = require 'ext.string'
local path = require 'ext.path'
local J = require 'java'

-- you can compile this with test_asmdex.lua
local dexfn = path'TestNative.dex'

-- ok i'm using TestNative.java to compare with ...
-- TODO I bet I could just read the .dex and then regenerate the same args with JavaLuaClass ...
local Test_luaclass_args = {
	env = J,
	isPublic = true,
	name = 'TestNative',
	parent = 'java.lang.Object',
	fields = {
		{
			isPublic = true,
			name = 'foo',
			sig = 'java.lang.String',
		},
		{
			isPublic = true,
			name = 'bar',
			sig = 'int',
		},
		{
			isPublic = true,
			name = 'baz',
			sig = 'double',
		},
	},
	ctors = {
		{
			isPublic = true,
			sig = {'void'},
			value = function(this) end,
		},
		{
			isPublic = true,
			sig = {'void', 'java.lang.Object'},
			value = function(this) end,
		},
		{
			isPublic = true,
			sig = {'void', 'int'},
			value = function(this) end,
		},
		{
			isPublic = true,
			sig = {'void', 'int', 'double'},
			value = function(this) end,
		},
		{
			isPublic = true,
			sig = {'void', 'double', 'int'},
			value = function(this) end,
		},
	},
	methods = {
		{
			isPublic = true,
			isStatic = true,
			name = 'test',
			sig = {'java.lang.String'},
			value = function() return 'Testing' end,
		},
		{
			isPublic = true,
			name = 'ol',
			sig = {'java.lang.String', 'long'},
			value = function() return 'ol_long' end,
		},
		{
			isPublic = true,
			name = 'ol',
			sig = {'java.lang.String', 'boolean'},
			value = function() return 'ol_boolean' end,
		},
		{
			isPublic = true,
			name = 'ol',
			sig = {'java.lang.String', 'short'},
			value = function() return 'ol_short' end,
		},
		{
			isPublic = true,
			name = 'ol',
			sig = {'java.lang.String', 'int'},
			value = function() return 'ol_int' end,
		},
		{
			isPublic = true,
			name = 'ol',
			sig = {'java.lang.String', 'float'},
			value = function() return 'ol_float' end,
		},
		{
			isPublic = true,
			name = 'ol',
			sig = {'java.lang.String', 'double'},
			value = function() return 'ol_double' end,
		},
		{
			isPublic = true,
			name = 'ol',
			sig = {'java.lang.String', 'java.lang.String'},
			value = function() return 'ol_String' end,
		},
		{
			isPublic = true,
			name = 'ol',
			sig = {'java.lang.String', 'java.lang.Object'},
			value = function() return 'ol_Object' end,
		},
		{
			isPublic = true,
			name = 'ol',
			sig = {'java.lang.String', 'char[]'},
			value = function() return 'ol_char_array' end,
		},
		{
			isPublic = true,
			name = 'foo',
			sig = {'void', 'int'},
			value = function() end,
		},
		{
			isPublic = true,
			name = 'foo',
			sig = {'void', 'java.lang.Object', 'int'},
			value = function() end,
		},
		{
			isPublic = true,
			name = 'foo',
			sig = {'void', 'java.lang.Object', 'double'},
			value = function() end,
		},
		{
			isPublic = true,
			name = 'foo',
			sig = {'void', 'double', 'java.lang.Object'},
			value = function() end,
		},
		{
			isPublic = true,
			name = 'getCount',
			sig = {'int'},
			value = function() end,
		},
		{
			isPublic = true,
			name = 'getItem',
			sig = {'java.lang.Object', 'int'},
			value = function() end,
		},
		{
			isPublic = true,
			name = 'getItemId',
			sig = {'long', 'int'},
			value = function() end,
		},
		{
			isPublic = true,
			name = 'getView',
			sig = {'java.lang.Object', 'int', 'java.lang.Object', 'java.lang.Object'},
			value = function() end,
		},
	},
}

Test_luaclass_args.returnASMArgsOnly = true
Test_luaclass_args.usingAndroidJNI = true	-- build for android even tho we're not on android
local Test_luaclass_asmArgs = require 'java.luaclass'(Test_luaclass_args)
local Test_luaclass_asm = require 'java.asmdex'(Test_luaclass_asmArgs)
local luaclassByteCode = Test_luaclass_asm:compile()
print('TestNative from java.luaclass:')
print(string.hexdump(luaclassByteCode))
print()

local Test_asmFromLuaClass = require 'java.asmdex'(luaclassByteCode)
print('TestNative from java.asmdex from java.luaclass:')
print(require 'ext.tolua'(Test_asmFromLuaClass))
print()

print('TestNative from .dex:')
local d8ByteCode = dexfn:read()
print(string.hexdump(d8ByteCode ))
print()
local Test_asmFromFile = require 'java.asmdex'(d8ByteCode)
print(require 'ext.tolua'(Test_asmFromFile))
print()
