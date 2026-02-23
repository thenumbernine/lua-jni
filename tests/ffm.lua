#!/usr/bin/env luajit
--[[
here's an attempt at the FFM (what the rest of the world calls "FFI" since the dawn of time, but I guess the folks at Java had to be special and call it "Project Panama".

Oops, I only have Java 21, but this requires Java 22, but it still shows up in the class search because Java 21 provided it as a "preview feature", which means it lies and says it's there when it's really not there.  Great java, Great.
--]]
local ffi = require 'ffi'
local J = require 'java.vm'{
	optionList = {
	--	'--enable-preview',						-- without this it warns but still runs
	--	'--enable-native-access=ALL-UNNAMED',	-- same
	},
}.jniEnv
assert(require 'java.class':isa(J.java.lang.foreign.Linker), "your Java doesn't have FFI, I mean, FFM")

callback = function(arg)
	print('hello from within Lua, arg', arg)
	return ffi.cast('void*', 1234567)
end
closure = ffi.cast('void *(*)(void*)', callback)

local signature = J.java.lang.foreign.FunctionDescriptor:of(
	J.java.lang.foreign.ValueLayout.JAVA_LONG,
	J.java.lang.foreign.ValueLayout.JAVA_LONG
)
print('signature', signature)

local linker = J.java.lang.foreign.Linker:nativeLinker()
print('linker', linker)

local functionPtrSeg = J.java.lang.foreign.MemorySegment:ofAddress(
	ffi.cast(J.long, closure)
)

local closureAsJavaFFMObj = linker:downcallHandle(
	functionPtrSeg,
	signature
)
print('closureAsJavaFFMObj', closureAsJavaFFMObj)

-- can't use invokeExact or you get "invokeexact cannot be invoked with reflection"
local result = closureAsJavaFFMObj:invokeWithArguments(
	-- J.long(42)	-- because invokeWithArguments() signature is an Object, it doesn't know to convert from a Long, so my java.method can't do auto-boxing
	J.java.lang.Long(42)
)
print('result', result)
