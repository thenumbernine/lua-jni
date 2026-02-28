#!/usr/bin/env luajit

-- test reading classdata
local path = require 'ext.path'
local string = require 'ext.string'
local JavaClassData = require 'java.classdata'

-- make sure it's built
require 'java.build'.java{
	dst = 'Test.class',
	src = 'Test.java',
}

local classFileData = assert(path'Test.class':read())

print('original:')
print(string.hexdump(classFileData))
print()

-- read
local cldata = JavaClassData(classFileData)
print('in Lua:')
print(require'ext.tolua'(cldata))
print()

-- write
local bytes = cldata:compile()
print'compiled:'
print(string.hexdump(bytes))
print()

print('2nd try, in Lua:')
local try2 = JavaClassData(bytes)
print(require'ext.tolua'(try2))
print()

local bytes = try2:compile()
print'2nd try, compiled:'
print(string.hexdump(bytes))
