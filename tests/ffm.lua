#!/usr/bin/env luajit
--[[
here's an attempt at the FFM (what the rest of the world calls "FFI" since the dawn of time, but I guess the folks at Java had to be special and call it "Project Panama".

Oops, I only have Java 21, but this requires Java 22, but it still shows up in the class search because Java 21 provided it as a "preview feature", which means it lies and says it's there when it's really not there.  Great java, Great.
--]]
local J = require 'java.vm'{
	optionList = {
		'--enable-preview',
		'--enable-native-access=ALL-UNNAMED',
	},
}.jniEnv
assert(require 'java.class':isa(J.java.lang.foreign.Linker), "your Java doesn't have FFI, I mean, FFM")

-- [====[ wholly separate demo, since FFM can't find strlen from libc

callback = function(arg)
	print('hello from within Lua, arg', arg)
	return 1234567
end
local ffi = require 'ffi'
closure = ffi.cast('void *(*)(void*)', callback)

-- [[
local signature = J.java.lang.foreign.FunctionDescriptor:of(
	J.java.lang.foreign.ValueLayout.JAVA_LONG,
	J.java.lang.foreign.ValueLayout.JAVA_LONG
)
print('signature', signature)

local linker = J.java.lang.foreign.Linker:nativeLinker()
print('linker', linker)

local functionPtrSeg = J.java.lang.foreign.MemorySegment:ofAddress(ffi.cast(J.long, closure))

local closureAsJavaFFMObj = linker:downcallHandle(
	functionPtrSeg,
	signature
)
print('closureAsJavaFFMObj', closureAsJavaFFMObj) 

local result = closureAsJavaFFMObj:invokeExact(J.long(42))
print('result', result)
--]]
--[[
local FunctionDescriptor = J.java.lang.foreign.FunctionDescriptor
print('FunctionDescriptor', FunctionDescriptor)
local FunctionDescriptor_of = FunctionDescriptor._members.of[1]
print('FunctionDescriptor.of', FunctionDescriptor_of)
local ValueLayout = J.java.lang.foreign.ValueLayout
print('ValueLayout',  ValueLayout)
print('ValueLayout.ADDRESS',  ValueLayout.ADDRESS)
local signature = FunctionDescriptor_of(
	FunctionDescriptor,
	ValueLayout.ADDRESS,
	ValueLayout.ADDRESS
)
--]]
os.exit()
--]====]



local javaString = J:_str"Hello FFM API!"
print('javaString', javaString)

local linker = J.java.lang.foreign.Linker:nativeLinker()
print('linker', linker)

local libC = linker:defaultLookup()
print('libC', libC)

local strlenAddress = libC:find("strlen"):orElseThrow()
print('strlenAddress', strlenAddress)

-- signature for `jlong stlren(char const*)`
local signature = J.java.lang.foreign.FunctionDescriptor:of(J.java.lang.foreign.ValueLayout.JAVA_LONG, J.java.lang.foreign.ValueLayout.ADDRESS)
print('signature', signature)

local strlen = linker:downcallHandle(strlenAddress, signature)
print('strlen', strlen)

local offHeap = J.java.lang.foreign.Arena:ofConfined()
print('offHeap', offHeap)

-- not available in Java 21, you'll have ot copy that string by hand
local cString = offHeap:allocateFrom(J.nio.charset.StandardCharsets.UTF_8, javaString)
print('cString', cString)

local len = strlen:invokeExact(cString)
print('len', len)

J.java.lang.System.out:println("Original Java String: \"" .. javaString .. "\"")
J.java.lang.System.out:println("Length calculated by C strlen(): " .. len)
J.java.lang.System.out:println("Length calculated by Java String.length(): " .. javaString:length())
-- TODO free offHeap
