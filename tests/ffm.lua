#!/usr/bin/env luajit
--[[
here's an attempt at the FFM (what the rest of the world calls "FFI" since the dawn of time, but I guess the folks at Java had to be special and call it "Project Panama".
--]]
local J = require 'java'
assert(require 'java.class':isa(J.java.lang.foreign.Linker), "your Java doesn't have FFI, I mean, FFM")

--[[ needs this to work
print('java.lang.String', J:_findClass'java.lang.String')
--[=[ so FindClass accepts signature based Ljava/lang/String; and just regular slash-separated java/lang/String ...
local String1 = J._ptr[0].FindClass(J._ptr, 'Ljava/lang/String;')
print('java.lang.String[] from JNIEnv->FindClass("Ljava/lang/String;")', String1)
local String2 = J._ptr[0].FindClass(J._ptr, 'java/lang/String')
print('java.lang.String[] from JNIEnv->FindClass("java/lang/String")', String2)
print('same?', J._ptr[0].IsSameObject(J._ptr, String1, String2))
--]=]
print('java.lang.String[] from String.class.arrayType()', J.java.lang.String:_class():arrayType())
print('java.lang.String[] from J:_findClass()', J:_findClass'java.lang.String[]')
print('java.lang.String[] from JNIEnv->FindClass("[Ljava/lang/String;")', J._ptr[0].FindClass(J._ptr, '[Ljava/lang/String;'))
--print('JNIEnv->FindClass("I")', J._ptr[0].FindClass(J._ptr, 'I'))
--print('JNIEnv->FindClass("int")', J._ptr[0].FindClass(J._ptr, 'int'))
print(J:_newArray('java.lang.String[][][]', 0))
os.exit()
--]]


-- [====[ wholly separate demo, since FFM can't find strlen from libc

callback = function(arg)
	print('hello from within Lua, arg', arg)
end
local ffi = require 'ffi'
closure = ffi.cast('void *(*)(void*)', callback)


--]====]



local javaString = J:_str"Hello FFM API!"
print('javaString', javaString)

local linker = J.java.lang.foreign.Linker:nativeLinker()
print('linker', linker)

local libC = linker:defaultLookup()
print('libC', libC)

local strlenAddress = libC:find("strlen"):orElseThrow()
print('strlenAddress', strlenAddress)

--[[
-- signature for `jlong stlren(char const*)`
local signature = J.java.lang.foreign.FunctionDescriptor:of(J.java.lang.foreign.ValueLayout.JAVA_LONG, J.java.lang.foreign.ValueLayout.ADDRESS)
--]]
-- [[ more callresolve woes
--print(J.java.lang.foreign.FunctionDescriptor._members.of:mapi(tostring):concat', ')
-- welp there is only one of these method signatures
-- but passing all the same stuff to it is giving a "JVM java.lang.NegativeArraySizeException: -471565071"
--  ...from calling.
local FunctionDescriptor = J.java.lang.foreign.FunctionDescriptor
print('FunctionDescriptor', FunctionDescriptor)
local FunctionDescriptor_of = FunctionDescriptor._members.of[1]
print('FunctionDescriptor.of', FunctionDescriptor_of)
local ValueLayout = J.java.lang.foreign.ValueLayout
print('ValueLayout',  ValueLayout)
print('ValueLayout.JAVA_LONG',  ValueLayout.JAVA_LONG)
print('ValueLayout.ADDRESS',  ValueLayout.ADDRESS)	-- because "pointer" would make too much sense.  corporate stupidity named this.
local signature = FunctionDescriptor_of(
	FunctionDescriptor,
	ValueLayout.JAVA_LONG,
	ValueLayout.ADDRESS
)
--]]
print('signature', signature)

local strlen = linker:downcallHandle(strlenAddress, signature)
print('strlen', strlen)

local offHeap = J.java.lang.foreign.Arena:ofConfined()
print('offHeap', offHeap)

local cString = offHeap:allocateFrom(J.nio.charset.StandardCharsets.UTF_8, javaString)
print('cString', cString)

local len = strlen:invokeExact(cString)
print('len', len)

J.java.lang.System.out:println("Original Java String: \"" .. javaString .. "\"")
J.java.lang.System.out:println("Length calculated by C strlen(): " .. len)
J.java.lang.System.out:println("Length calculated by Java String.length(): " .. javaString:length())
-- TODO free offHeap
