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
print(require'ext.tolua'(cldata))
print()

-- write
local bytes = cldata:compile()
print'compiled:'
print(string.hexdump(bytes))
