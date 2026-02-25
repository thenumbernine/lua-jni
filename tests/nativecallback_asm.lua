--[[
equivalent of ./io/github/thenumbernine/NativeCallback.java
and its JNI .so
--]]
local path = require 'ext.path'

return function(J)
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
	cw:visitMethod(bit.bor(Opcodes.ACC_NATIVE, Opcodes.ACC_PUBLIC, Opcodes.ACC_STATIC), 'run', '(JJ)V', nil, nil)
		:visitEnd()

	--}
	cw:visitEnd()

	local code = cw:toByteArray()

	-- create the java .class to go along with it
	local classAsObj = require 'java.tests.bytecodetoclass'
		.URIClassLoader(J, code, newClassName)

	return (J:_getClassForJClass(classAsObj._ptr))
end
