--[[
equivalent of ./io/github/thenumbernine/NativeCallback.java
and its JNI .so

TODO how about a separate class that accepts a Lua callback
and a subclass ... Single-Abstract-Method or whatever
and then packages the SAM args into an Object[]
and then forwards the jobject to the NativeCallback's C arg
and then maybe we have an extra wrapping function to the callback to translate the args from Java Object[] entries to Lua when applicable ... nil, String, prims, ...array?, etc
--]]
local path = require 'ext.path'

local M = {}
function M:run(J)
	if M.cache then return M.cache end

	-- need to build the jni .c side
	require 'java.build'.C{
		src = 'io_github_thenumbernine_NativeCallback.c',
		dst = 'libio_github_thenumbernine_NativeCallback.so',
	}

	local ClassWriter = J.org.objectweb.asm.ClassWriter
	assert(require 'java.class':isa(ClassWriter), "JRE isn't finding ASM")
	local cw = ClassWriter(ClassWriter.COMPUTE_FRAMES)

	local Opcodes = J.org.objectweb.asm.Opcodes

	local newClassName = 'io/github/thenumbernine/NativeCallback'
	cw:visit(
		Opcodes.V1_6,
		Opcodes.ACC_PUBLIC,
		newClassName,
		nil,
		'java/lang/Object',
		nil)

	--	static
	local clinit = cw:visitMethod(Opcodes.ACC_STATIC, '<clinit>', '()V', nil, nil)
	--	{
	clinit:visitCode()
	clinit:visitLdcInsn((path:cwd()/'libio_github_thenumbernine_NativeCallback.so').path)
	--	call System.loadLibrary
	clinit:visitMethodInsn(Opcodes.INVOKESTATIC, 'java/lang/System', 'load', '(Ljava/lang/String;)V', false)
	--	return
	clinit:visitInsn(Opcodes.RETURN)
	--	max stacks, locals
	clinit:visitMaxs(1, 0)
	--	}
	clinit:visitEnd()

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

	local code = cw:toByteArray()

	-- create the java .class to go along with it
	local classAsObj = require 'java.tests.bytecodetoclass'(J, code, newClassName)

	M.cache = (J:_getClassForJClass(classAsObj._ptr))
	return M.cache
end
setmetatable(M, {
	__call = M.run,
})
return M
