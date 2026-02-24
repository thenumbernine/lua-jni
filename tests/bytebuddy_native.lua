#!/usr/bin/env luajit
--[[
bytebuddy.lua creates a new class and overrides its toString()
ffm.lua creates a new MethodHandle that can call into a C closure pthread void*(*)(void*)

now to combine them, to make a ByteBuddy class whose run() method calls a MethodHandle.invokeWithArguments
--]]

-- [[ init JVM for byte-buddy, and optionally stupid cli flags to silence stupid warnings
local J = require 'java.vm'{
	optionList = {
		'--enable-preview',						-- without this it warns but still runs
		'--enable-native-access=ALL-UNNAMED',	-- same
	},
	props = {
		['java.class.path'] = table.concat({
			'byte-buddy-1.18.5.jar',
			'.',
		}, ':'),
	},
}.jniEnv
local JavaClass = require 'java.class'
assert(JavaClass:isa(J.net.bytebuddy.ByteBuddy), "I can't find the ByteBuddy jar...")
assert(JavaClass:isa(J.java.lang.foreign.Linker), "your Java doesn't have FFI, I mean, FFM")
--]]

-- [[ here's our LuaJIT callback.  no args, cuz it's going in a Runnable in ByteBuddy
local ffi = require 'ffi'
callback = function()
	print('hello from within Lua')
end
closure = ffi.cast('void(*)()', callback)
--]]

-- [[ here's our Java FFM method
local signature = J.java.lang.foreign.FunctionDescriptor:ofVoid()
print('signature', signature)

local linker = J.java.lang.foreign.Linker:nativeLinker()
print('linker', linker)

local functionPtrSeg = J.java.lang.foreign.MemorySegment:ofAddress(ffi.cast(J.long, closure))

local closureJavaMethodHandle = linker:downcallHandle(functionPtrSeg, signature)
print('closureJavaMethodHandle', closureJavaMethodHandle)

closureJavaMethodHandle:invokeWithArguments()
--]]

-- [[ here's our ByteBuddy

local Runnable_classObj = J.Runnable:_class()
local bb = J.net.bytebuddy.ByteBuddy()
bb = bb:subclass(Runnable_classObj)
	
bb = bb:method(J.net.bytebuddy.matcher.ElementMatchers:named'run')

	-- 2500 different classes to this package.  and no solid tutorial.

	--:defineMethod('run', J.Void.TYPE, J.org.objectweb.asm.Opcodes.ACC_PUBLIC)
		--J.net.bytebuddy.implementation.FixedValue:value(
	
	-- [[ "not a direct method handle"
	bb = bb:intercept(J.net.bytebuddy.utility['JavaConstant$MethodHandle']:ofLoaded(closureJavaMethodHandle))
	--]]

	--[[
	bb = bb:intercept(
		J.net.bytebuddy.implementation.MethodCall:invoke(closureJavaMethodHandle)
	)
	--]]
		--J.net.bytebuddy.implementation.InvokeDynamic:bootstrap(closureJavaMethodHandle, J.Long(42))
		--J.net.bytebuddy.implementation.InvokeDynamic(closureJavaMethodHandle):withLongValue(J.long(42))
			--[[
	bb = bb:intercept(
		J.net.bytebuddy.implementation.InvokeDynamic:bootstrap(
			J.java.lang.invoke.MethodHandles:constant(
				J.java.lang.invoke.MethodHandle:_class(),
				closureJavaMethodHandle
			)
		)
	)
			--]]
			--[[
	bb = bb:intercept(
		J.net.bytebuddy.implementation.InvokeDynamic:bootstrap(
			J.net.bytebuddy.matcher.ElementMatchers:is(
				Runnable_classObj:getDeclaredMethods()[0] -- Using index might be fragile; better to use ElementMatchers.named("bootstrap") if possible in the actual API
			)
		):withTargetMethod(
			J.java.lang.invoke.MethodType:methodType(
				J.Void.TYPE -- The signature of the invokedynamic instruction
			)
		):withReference(
			J.java.lang.invoke.MethodType:_class(),
			J.java.lang.invoke.MethodType:methodType(J.Void.TYPE) -- An extra constant argument if needed, here just an example
		)
	)
	
			--]]

bb = bb:make()
bb = bb:load(Runnable_classObj:getClassLoader())
local dynamicType = bb:getLoaded()

-- now dynamicType is a Java object of type java.lang.Class<?>, where the ? is java.lang.Object because that's what I fed into :subclass() and :load() above
print('dynamicType', dynamicType, dynamicType._classpath)
local dynamicObj = dynamicType:getDeclaredConstructor():newInstance()
print('dynamicObj', dynamicObj)

--]]
