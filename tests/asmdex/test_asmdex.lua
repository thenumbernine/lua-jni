#!/usr/bin/env luajit
-- this recompiles , then .dex's the Test.java file, same as test_asmclass.lua
local os = require 'ext.os'
local table = require 'ext.table'
local path = require 'ext.path'
local string = require 'ext.string'
local assert = require 'ext.assert'
local JavaASMDex = require 'java.asmdex'

--local srcfn = path'Test.java'
local srcfn = path'TestNative.java'
--local srcfn = path'TestToString.java'
--local srcfn = path'io/github/thenumbernine/NativeCallback.java'
assert(srcfn:exists(), "couldn't find java file "..srcfn)

assert(os.exec('javac '..srcfn))		-- mind you this is openjdk's verison, not android studio's version
local classfn = srcfn:setext'class'
assert(classfn:exists(), "javac didn't produce a class file "..classfn)

--local androidPath = path(assert(os.getenv'ANDROID_HOME'))/'jbr/bin'	-- path to android studio's javac java etc

local toolsVersionsDir = (path(assert(os.home()))/'Android/Sdk/build-tools')
local toolsVersion = table.wrapfor(toolsVersionsDir :dir())
	:mapi(function(vk) return vk[1] end)
	:sort()
	:last()
local toolsDir = toolsVersionsDir/toolsVersion  	-- path to d8 etc
print('toolsDir', toolsDir)
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

-------- first file

print('original bytecode:')
print(string.hexdump(dexBC, 16))
print()

print'dexdump'
io.stdout:flush()
os.exec(toolsDir/'dexdump'..' '..dexfn..' 2>&1')
io.stdout:flush()
print()

local asmDex = JavaASMDex(dexBC)
print('JavaASMDex:')
print(require'ext.tolua'(asmDex))	-- original bytecode's lua structure
print()

-------- second file

local bytes = asmDex:compile()
print'recompiled bytecode:'
print(string.hexdump(bytes, 16))
print()

local tmp = path'tmp.dex'
tmp:write(bytes)
print'dexdump'
io.stdout:flush()
os.exec(toolsDir/'dexdump'..' '..tmp..' 2>&1')
io.stdout:flush()
print()
tmp:remove()

print('2nd read into JavaASMDex:')
local try2 = JavaASMDex(bytes)
print(require'ext.tolua'(try2))		-- write #1 bytecode's lua structure
print()

-------- third file

local bytes2 = try2:compile()
print'2nd recompiled bytecode:'
print(string.hexdump(bytes2, 16))
if bytes ~= bytes2 then error("recompile didn't match first compile") end

tmp:write(bytes2)
print'dexdump'
io.stdout:flush()
os.exec(toolsDir/'dexdump'..' '..tmp..' 2>&1')
io.stdout:flush()
print()
tmp:remove()

print('2nd recompiled into JavaASMDex:')
local try3 = JavaASMDex(bytes2)
print(require'ext.tolua'(try3))		-- write #1 bytecode's lua structure


-- TODO here use java-asm's validator to spit out stuff about it
-- TODO maybe here too use javap to spit out stuff about it
