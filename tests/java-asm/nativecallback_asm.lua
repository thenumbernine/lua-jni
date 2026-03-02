--[[
equivalent of ./io/github/thenumbernine/NativeCallback.java
and its JNI .so

This returns a function(J) that returns a JavaClass
 with the field _runMethodName set to its native static method
 with signature Object(long, Object)
 that is used for callbacks of pthread signature function pointers.
--]]
local ffi = require 'ffi'
local path = require 'ext.path'

local M = {}

M.nativeCallbackRunFunc = function(jniEnvPtr, this, jfuncptr, jarg)
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

function M:run(J)
	local newClassName = 'io/github/thenumbernine/NativeCallback'

	-- check if it's already loaded
	local cl = J:_findClass(newClassName)
	if cl then
		rawset(cl, '_runMethodName', 'run')
		return cl
	end

	local ClassWriter = J.org.objectweb.asm.ClassWriter
	local JavaClass = require 'java.class'
	assert(JavaClass:isa(ClassWriter), "JRE isn't finding ASM")
	local cw = ClassWriter(ClassWriter.COMPUTE_FRAMES)

	local Opcodes = J.org.objectweb.asm.Opcodes

	cw:visit(
		Opcodes.V1_6,
		Opcodes.ACC_PUBLIC,
		newClassName,
		nil,
		'java/lang/Object',
		nil)

	-- public static native long run(long funcptr, long arg);
	cw:visitMethod(
		bit.bor(Opcodes.ACC_NATIVE, Opcodes.ACC_PUBLIC, Opcodes.ACC_STATIC),
		'run',
		'(JLjava/lang/Object;)Ljava/lang/Object;',
		nil,
		nil
	):visitEnd()

	--}
	cw:visitEnd()

	-- create the java .class to go along with it
	local classAsObj = require 'java.tests.bytecodetoclass'(J, cw:toByteArray():_toStr(), newClassName)

	local cl = J:_fromJClass(classAsObj._ptr)

	J._ptr[0].RegisterNatives(J._ptr, cl._ptr, M.nativeMethods, 1)

	-- save for later:
	rawset(cl, '_runMethodName', 'run')

	return cl
end

return setmetatable(M, {
	__call = M.run,
})
