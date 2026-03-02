#!/usr/bin/env luajit
-- this loads a `.class` and spits out its JavaASMClass contents.
-- Useful for viewing Java disassembly.
-- The equivalent contents can be taken and used as a JavaASMClass ctor args to build a similar class. 
--  (Should be the identical class bytecode if disassembled and built twice in a row from JavaASMClass)
-- (TODO this is the same as java/tests/javac/test_asmclass.lua except that runs java-asm and maybe the javap stuff too)
local path = require 'ext.path'
local string = require 'ext.string'
local assert = require 'ext.assert'
local JavaASMClass = require 'java.asmclass'

local classfile = path((assert(..., 'expected <classfile>')))
assert(classfile:exists(), "couldn't find class file "..classfile)
local classFileData = assert(classfile:read())

print(classfile)
print()

print('original bytecode:')
print(string.hexdump(classFileData, 48))
print()

local cldata = JavaASMClass(classFileData)
print('JavaASMClass:')
print(require'ext.tolua'(cldata))
print()

local bytes = cldata:compile()
print'recompiled bytecode:'
print(string.hexdump(bytes, 48))
print()

print('2nd read into JavaASMClass:')
local try2 = JavaASMClass(bytes)
print(require'ext.tolua'(try2))
print()

local bytes2 = try2:compile()
print'2nd recompiled bytecode:'
print(string.hexdump(bytes2, 48))
assert.eq(bytes, bytes2)

-- TODO here use java-asm's validator to spit out stuff about it
-- TODO maybe here too use javap to spit out stuff about it
