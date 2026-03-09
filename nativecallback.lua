--[[
Here's the fake-class used for the solve purpose of its one native function that a lot of other functions are using for Java calling into LuaJIT.
I guess with JavaASMClass and JavaLuaClass, the need for this is getting slimmer and slimmer...
--]]
local ffi = require 'ffi'
local template = require 'template'

local M = {}

M.nativeCallbackRunFunc = function(env, this, jfuncptr, jarg)
	local vfptr = ffi.cast('void*', jfuncptr)
	local results
	if vfptr == nil then
		io.stderr:write("!!! DANGER !!! NativeCallback called with null function pointer !!!\n")
	else
		-- in LuaJIT if I cast cdata to a function-pointer, does it create another closure object that I have to manually free?  I think no ...
		local fptr = ffi.cast('void*(*)(void*)', vfptr)
		results = fptr(jarg)
	end
	return results
end
M.nativeCallbackRunClosure = ffi.cast('jobject(*)(JNIEnv * env, jclass this_, jlong jfuncptr, jobject jarg)', M.nativeCallbackRunFunc)

M.runMethodName = 'run'
M.runMethodSig = '(JLjava/lang/Object;)Ljava/lang/Object;'

-- if Lua gc's this will Java complain?  Does Java copy it over upon function call?  I don't trust JNI's programmers....
M.nativeMethods = ffi.new'JNINativeMethod[1]'
M.nativeMethods[0].name = M.runMethodName
M.nativeMethods[0].signature = M.runMethodSig
M.nativeMethods[0].fnPtr = M.nativeCallbackRunClosure

function M:run(env)
	local newClassName = 'io.github.thenumbernine.NativeCallback'

	-- check if it's already loaded
	local cl = env:_findClass(newClassName)
	if cl then
		rawset(cl, '_runMethodName', M.runMethodName)
		return cl
	end

	local asmClass
	-- you will have to set this,
	-- TODO infer if we're in Android somehow, maybe reaad a property or something?
	if env._usingAndroidJNI then
		local JavaASMDex = require 'java.asmdex'
		asmClass = JavaASMDex:fromAsm(template([[
.class public <?=newClassName?>	# no super? what does that do again?
.super java.lang.Object
.method public constructor <init> ()V
	.registers 1 1 1
	invoke-direct Ljava/lang/Object; <init> ()V	v0
	return-void
.end method
.method public static native <?=runMethodName?> <?=runMethodSig?>
]],		{
			newClassName = newClassName,
			runMethodName = M.runMethodName,
			runMethodSig = M.runMethodSig,
		}))
	else
		local JavaASMClass = require 'java.asmclass'
		asmClass = JavaASMClass:fromAsm(template([[
.class public super <?=newClassName?>
.super java.lang.Object
.method public <init> ()V
	aload_0		# push 'this'
	invokespecial java.lang.Object <init> ()V	# call ((java.lang.Object)this).<init>()
	return		# aka return-void ... should I try to match up the syntaxes?
.end method
.method public static native <?=runMethodName?> <?=runMethodSig?>
.end method
]], 	{
			newClassName = newClassName,
			runMethodName = M.runMethodName,
			runMethodSig = M.runMethodSig,
		}))
	end

	local cl = env:_defineClass(asmClass)

	-- now it looks like JNIEnv->RegisterNatives can allow you to manually set native methods instead of depending on symbol table.
	-- but I'm also reading that JNIEnv->RegisterNatives itself needs to be called from ... a specifically-named function in the symbol table ... smh.
	-- let's see if I can call it manually here ...
	env._ptr[0].RegisterNatives(env._ptr, cl._ptr, M.nativeMethods, 1)

	rawset(cl, '_runMethodName', M.runMethodName)
	return cl
end

return setmetatable(M, {
	__call = M.run,
})
