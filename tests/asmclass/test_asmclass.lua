#!/usr/bin/env luajit

-- test reading and writing and reading and writing asmclass
local os = require 'ext.os'
local path = require 'ext.path'
local assert = require 'ext.assert'
local string = require 'ext.string'
local JavaASMClass = require 'java.asmclass'


-- [[
local srcClassPath = path'../test/Test.class'
srcClassPath:remove()
--]]
--[[
local srcClassPath = path'io/github/thenumbernine/NativeCallback.class'
--]]
--[[
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
			'../java-asm/asm-9.9.1.jar',		-- needed for ASM, for ClassReader, for validating integrity of class
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

	-- need this subclass
	require 'make.targets'():add{
		dsts = {'TestClassVisitor.class'},
		srcs = {'TestClassVisitor.java'},
		rule = function(r)
			assert(os.exec('javac -cp ../java-asm/asm-9.9.1.jar TestClassVisitor.java'))
		end,
	}:runAll()

	local vis = J.TestClassVisitor()
	cr:accept(vis, 0)
	print'END VALIDATION'
end



validate()

local classByteCode = assert(srcClassPath:read())

print('original:')
print(string.hexdump(classByteCode, 16))
print()

-- read
local cldata = JavaASMClass(classByteCode)
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
local try2 = JavaASMClass(bytes)
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
