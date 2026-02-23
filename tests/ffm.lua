#!/usr/bin/env luajit
--[[
here's an attempt at the FFM (what the rest of the world calls "FFI" since the dawn of time, but I guess the folks at Java had to be special and call it "Project Panama".
--]]
local J = require 'java'
assert(require 'java.class':isa(J.java.lang.foreign.Linker), "your Java doesn't have FFI, I mean, FFM")

local javaString = J:_str"Hello FFM API!"
print('javaString', javaString)

-- 1. Obtain the native linker and a lookup object for standard libraries
local linker = J.java.lang.foreign.Linker:nativeLinker()
print('linker', linker)
local libC = linker:defaultLookup()
print('libC', libC)

-- 2. Find the address of the "strlen" function in the standard library
local strlenAddress = libC:find("strlen"):orElseThrow()
print('strlenAddress', strlenAddress)

-- 3. Define the function signature (return type: long, argument type: address/pointer)
local signature = J.java.lang.foreign.FunctionDescriptor:of(J.java.lang.foreign.ValueLayout.JAVA_LONG, J.java.lang.foreign.ValueLayout.ADDRESS)

-- 4. Obtain a method handle for the native function call (downcall)
local strlen = linker:downcallHandle(strlenAddress, signature)

-- 5. Use a confined Arena to manage the lifetime of off-heap memory

local offHeap = J.java.lang.foreign.Arena:ofConfined()

-- 6. Allocate off-heap memory and copy the Java string into it as a null-terminated C string
local cString = offHeap:allocateFrom(J.nio.charset.StandardCharsets.UTF_8, javaString)

-- 7. Invoke the native strlen function using the method handle
local len = strlen:invokeExact(cString)

J.java.lang.System.out:println("Original Java String: \"" .. javaString .. "\"")
J.java.lang.System.out:println("Length calculated by C strlen(): " .. len)
J.java.lang.System.out:println("Length calculated by Java String.length(): " .. javaString:length())
-- When the try-with-resources block exits, the off-heap memory in 'offHeap' arena is automatically freed
