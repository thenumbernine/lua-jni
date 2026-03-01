#!/usr/bin/env luajit

-- test reading classdata
local os = require 'ext.os'
local path = require 'ext.path'
local assert = require 'ext.assert'
local string = require 'ext.string'
local JavaClassData = require 'java.classdata'


local TestClassPath = path'Test.class'
-- make sure it's built from the original
TestClassPath:remove()
require 'java.build'.java{
	dst = 'Test.class',
	src = 'Test.java',
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
	local bytes = assert(TestClassPath:read())
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

local classFileData = assert(TestClassPath:read())

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
TestClassPath:write(bytes)
validate()
--]=] 

-- stdout / stderr flush issues, when piping even >&1 it is out of order 
--os.exec'javap Test.class'


print'DONE'
