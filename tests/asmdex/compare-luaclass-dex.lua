#!/usr/bin/env luajit
--[[
build something in dex
compare it to JavaASMDex
--]]
local string = require 'ext.string'
local path = require 'ext.path'
local J = require 'java'

-- you can compile the .dex file with test_asmdex.lua

--[====[ comparison for TestNative
local dexfn = path'TestNative.dex'
-- ok i'm using TestNative.java to compare with ...
-- TODO I bet I could just read the .dex and then regenerate the same args with JavaLuaClass ...
local luaClassArgs = {
	env = J,
	isPublic = true,
	name = 'TestNative',
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
--]====]
-- [====[ comparison for TestGLSurfaceViewRenderer
local dexfn = path'TestGLSurfaceViewRenderer.dex'
local luaClassArgs = {
	env = J,
	isPublic = true,
	name = 'TestGLSurfaceViewRenderer',
	implements = {
		'android.opengl.GLSurfaceView$Renderer',
	},
	methods = {
		{
			isPublic = true,
			name = 'onSurfaceCreated',
			sig = {
				'void',
				'javax.microedition.khronos.opengles.GL10',
				'javax.microedition.khronos.egl.EGLConfig',
			},
			value = function() end,
		},
		{
			isPublic = true,
			name = 'onSurfaceChanged',
			sig = {
				'void',
				'javax.microedition.khronos.opengles.GL10',
				'int',
				'int',
			},
			value = function() end,
		},
		{
			isPublic = true,
			name = 'onDrawFrame',
			sig = {
				'void',
				'javax.microedition.khronos.opengles.GL10',
			},
			value = function() end,
		},
	},
}
--]====]

luaClassArgs.returnASMArgsOnly = true
luaClassArgs.usingAndroidJNI = true	-- build for android even tho we're not on android
local luaClassAsmArgs = require 'java.luaclass'(luaClassArgs)
local luaClassAsm = require 'java.asmdex'(luaClassAsmArgs)
local luaclassByteCode = luaClassAsm:compile()

local fa = assert(io.open('compare-a.txt', 'w'))

fa:write'TestNative from java.luaclass:\n'
fa:write(string.hexdump(luaclassByteCode), '\n')
fa:write'\n'

local Test_asmFromLuaClass = require 'java.asmdex'(luaclassByteCode)
fa:write'TestNative from java.asmdex from java.luaclass:\n'
fa:write(require 'ext.tolua'(Test_asmFromLuaClass), '\n')
fa:write'\n'
fa:close()

local fb = assert(io.open('compare-b.txt', 'w'))
fb:write'TestNative from .dex:\n'
local d8ByteCode = dexfn:read()
fb:write(string.hexdump(d8ByteCode ), '\n')
fb:write'\n'

local Test_asmFromFile = require 'java.asmdex'(d8ByteCode)
fb:write(require 'ext.tolua'(Test_asmFromFile), '\n')
fb:write'\n'
fb:close()
