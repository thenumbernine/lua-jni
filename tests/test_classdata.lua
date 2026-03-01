#!/usr/bin/env luajit

-- test reading classdata
local os = require 'ext.os'
local path = require 'ext.path'
local assert = require 'ext.assert'
local string = require 'ext.string'
local JavaClassData = require 'java.classdata'


--[[
local srcClassPath = path'Test.class'
srcClassPath:remove()
--]]
--[[
local srcClassPath = path'io/github/thenumbernine/NativeCallback.class'
--]]
-- [[
local srcClassPath = path'io/github/thenumbernine/NativeRunnable.class'
--]]

-- make sure it's built from the original
require 'java.build'.java{
	dst = srcClassPath.path,
	src = srcClassPath:setext'java',
}


-- validate it with java-asm
local J = require 'java.vm'{
	props = {
		['java.class.path'] = table.concat({
			'.',
			'asm-9.9.1.jar',		-- needed for ASM
		}, ':'),
		['java.library.path'] = '.',
	},
}.jniEnv
local ClassReader = J.org.objectweb.asm.ClassReader
assert(require 'java.class':isa(ClassReader), "JRE isn't finding ASM")

local function validate()
	print'BEGIN VALIDATION'
	io.stdout:flush()	-- java stdout/sterr flush issues as always
	local bytes = assert(srcClassPath:read())
	local jbytes = J:_newArray('byte', #bytes)
	local ptr = jbytes:_map()
	local ffi = require 'ffi'
	ffi.copy(ptr, bytes, #bytes)
	jbytes:_unmap(ptr)
	local cr = ClassReader(jbytes)
	local vis = J.TestClassVisitor()
	cr:accept(vis, 0)
	print'END VALIDATION'
end



validate()

local classFileData = assert(srcClassPath:read())

print('original:')
print(string.hexdump(classFileData, 16))
print()

-- read
local cldata = JavaClassData(classFileData)
print('in Lua:')
print(require'ext.tolua'(cldata))
print()

-- [=[
-- write
local bytes = cldata:compile()
print'compiled:'
print(string.hexdump(bytes, 16))
print()

print('2nd try, in Lua:')
local try2 = JavaClassData(bytes)
print(require'ext.tolua'(try2))
print()

local bytes2 = try2:compile()
print'2nd try, compiled:'
print(string.hexdump(bytes2, 16))
assert.eq(bytes, bytes2)

-- write our new
-- overwrite it
-- I'd keep it separate but meh, it's java, it wants the classname to match the filename
srcClassPath:write(bytes)
validate()
--]=] 

-- stdout / stderr flush issues, when piping even >&1 it is out of order 
--os.exec('javap '..srcClassPath)


print'DONE'
