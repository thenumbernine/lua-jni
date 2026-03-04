#!/usr/bin/env luajit
-- this loads a `.dex` and spits out its JavaASMDex contents.
-- same idea as tests/asmclass/disasm.lua
local os = require 'ext.os'
local path = require 'ext.path'
local string = require 'ext.string'
local assert = require 'ext.assert'
local JavaASMDex = require 'java.asmdex'

local dexfn = path(( assert(..., "expected dex filename") ))
local dexBC = assert(dexfn:read())

print(dexfn)
print()

print('original bytecode:')
print(string.hexdump(dexBC, 48))
print()

local asmDex = JavaASMDex(dexBC)
print('JavaASMDex:')
print(require'ext.tolua'(asmDex))
print()

--[[
local bytes = asmDex:compile()
print'recompiled bytecode:'
print(string.hexdump(bytes, 48))
print()

print('2nd read into JavaASMDex:')
local try2 = JavaASMDex(bytes)
print(require'ext.tolua'(try2))
print()

local bytes2 = try2:compile()
print'2nd recompiled bytecode:'
print(string.hexdump(bytes2, 48))
assert.eq(bytes, bytes2)

-- TODO here use java-asm's validator to spit out stuff about it
-- TODO maybe here too use javap to spit out stuff about it
--]]
