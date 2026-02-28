#!/usr/bin/env luajit

-- test reading classdata
local os = require 'ext.os'
local path = require 'ext.path'
local assert = require 'ext.assert'
local string = require 'ext.string'
local JavaClassData = require 'java.classdata'

-- make sure it's built from the original
path'Test.class':remove()
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

--[=[
-- write
local bytes = cldata:compile()
print'compiled:'
print(string.hexdump(bytes))
print()

print('2nd try, in Lua:')
local try2 = JavaClassData(bytes)
print(require'ext.tolua'(try2))
print()

local bytes2 = try2:compile()
print'2nd try, compiled:'
print(string.hexdump(bytes))
assert.eq(bytes, bytes2)

print'DONE'
-- write our new
path'Test.class':write(bytes)

-- stdout / stderr flush issues, when piping even >&1 it is out of order 
--os.exec'javap Test.class'
--]=]
