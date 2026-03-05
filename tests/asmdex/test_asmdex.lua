#!/usr/bin/env luajit
-- this recompiles , then .dex's the Test.java file, same as test_asmclass.lua 
local os = require 'ext.os'
local path = require 'ext.path'
local string = require 'ext.string'
local assert = require 'ext.assert'
local JavaASMDex = require 'java.asmdex'

local srcfn = path'Test.java' 
assert(srcfn:exists(), "couldn't find java file "..srcfn)

assert(os.exec('javac '..srcfn))		-- mind you this is openjdk's verison, not android studio's version
local classfn = srcfn:setext'class'
assert(classfn:exists(), "javac didn't produce a class file "..classfn)

--local androidPath = path(assert(os.getenv'ANDROID_HOME'))/'jbr/bin'	-- path to android studio's javac java etc
local toolsDir = path(assert(os.home()))/'Android/Sdk/build-tools/36.0.0'	-- path to d8 etc 
local d8 = toolsDir/'d8'
assert(d8:exists())

local classesDexFn = path'classes.dex'	-- to make d8 produce a dex file you need to set its --output to a folder, then it writes in that folder 'classes.dex' ...
assert(os.exec(d8..' --output . '..classfn))
assert(classesDexFn:exists(), "d8 didn't produce a dex file "..classesDexFn)

local dexfn = srcfn:setext'dex'
classesDexFn:move(dexfn)
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
if bytes ~= bytes2 then error("recompile didn't match first compile") end

-- TODO here use java-asm's validator to spit out stuff about it
-- TODO maybe here too use javap to spit out stuff about it
