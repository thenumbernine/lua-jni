#!/usr/bin/env luajit
-- this loads a `.class` and spits out its JavaClassData contents.
-- Useful for viewing Java disassembly.
-- The equivalent contents can be taken and used as a JavaClassData ctor args to build a similar class. 
--  (Should be the identical class bytecode if disassembled and built twice in a row from JavaClassData)
-- (TODO this is the same as java/tests/javac/test_classdata.lua except that runs java-asm and maybe the javap stuff too)
local path = require 'ext.path'
local string = require 'ext.string'
local assert = require 'ext.assert'
local JavaClassData = require 'java.classdata'

local classfile = path((assert(..., 'expected <classfile>')))
assert(classfile:exists(), "couldn't find class file "..classfile)
local classFileData = assert(classfile:read())

print(classfile)
print()

print('original bytecode:')
print(string.hexdump(classFileData, 48))
print()

local cldata = JavaClassData(classFileData)
print('JavaClassData:')
print(require'ext.tolua'(cldata))
print()

local bytes = cldata:compile()
print'recompiled bytecode:'
print(string.hexdump(bytes, 48))
print()

print('2nd read into JavaClassData:')
local try2 = JavaClassData(bytes)
print(require'ext.tolua'(try2))
print()

local bytes2 = try2:compile()
print'2nd recompiled bytecode:'
print(string.hexdump(bytes2, 48))
assert.eq(bytes, bytes2)

-- TODO here use java-asm's validator to spit out stuff about it
-- TODO maybe here too use javap to spit out stuff about it
