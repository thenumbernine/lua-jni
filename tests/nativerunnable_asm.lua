--[[
This at least offloads the .java->.class side of things to LuaJIT
But it still requires a separate .so
--]]
local path = require 'ext.path'

return function(J)
	-- still need to build the jni side
	require 'java.build'.C{
		src = 'io_github_thenumbernine_NativeRunnable.c',
		dst = 'libio_github_thenumbernine_NativeRunnable.so',
	}

	-- create the java .class to go along with it
	local newClassName = 'io/github/thenumbernine/NativeRunnable'

	local ClassWriter = J.org.objectweb.asm.ClassWriter
	assert(require 'java.class':isa(ClassWriter), "JRE isn't finding ASM")
	local cw = ClassWriter(ClassWriter.COMPUTE_FRAMES)

	-- can I make this use the same namespace as my previously built .so?
	local Opcodes = J.org.objectweb.asm.Opcodes

	--public class DynamicNativeRunnable extends java.lang.Object {
	cw:visit(Opcodes.V1_8, Opcodes.ACC_PUBLIC, newClassName, nil, 'java/lang/Object', nil)

	--	static
	local clinit = cw:visitMethod(Opcodes.ACC_STATIC, '<clinit>', '()V', nil, nil)
	--	{
	clinit:visitCode()
	--	push "DynamicNativeRunnable"	-- this location gives "JVM java.lang.UnsatisfiedLinkError: Expecting an absolute path of the library: ./libDynamicNativeRunnable.so"
	--clinit:visitLdcInsn((path:cwd()/'libDynamicNativeRunnable.so').path)
	clinit:visitLdcInsn((path:cwd()/'libio_github_thenumbernine_NativeRunnable.so').path)
	--	call System.loadLibrary
	clinit:visitMethodInsn(Opcodes.INVOKESTATIC, 'java/lang/System', 'load', '(Ljava/lang/String;)V', false)
	--	return
	clinit:visitInsn(Opcodes.RETURN)
	--	max stacks, locals
	clinit:visitMaxs(1, 0)
	--	}
	clinit:visitEnd()

	--	long funcptr;
	cw:visitField(Opcodes.ACC_PUBLIC, 'funcptr', 'J', nil, nil)
		:visitEnd()

	-- long arg;
	cw:visitField(Opcodes.ACC_PUBLIC, 'arg', 'J', nil, nil)
		:visitEnd()

	--	public DynamicNativeRunnable(long funcptr, long arg)
	local init = cw:visitMethod(Opcodes.ACC_PUBLIC, '<init>', '(JJ)V', nil, nil)
	--	{
	init:visitCode()
	--		push 'this'
	init:visitVarInsn(Opcodes.ALOAD, 0)
	--		call super() aka java.lang.Object();
	init:visitMethodInsn(Opcodes.INVOKESPECIAL, 'java/lang/Object', '<init>', '()V', false)
	--		push 'this'
	init:visitVarInsn(Opcodes.ALOAD, 0)
	--		push arg #1
	init:visitVarInsn(Opcodes.LLOAD, 1)
	--		this.funcptr = arg #1
	init:visitFieldInsn(Opcodes.PUTFIELD, newClassName, 'funcptr', 'J')
	--		push 'this'
	init:visitVarInsn(Opcodes.ALOAD, 0)
	--		push arg #2 (index 3)
	init:visitVarInsn(Opcodes.LLOAD, 3)
	--		this.funcptr = arg #2
	init:visitFieldInsn(Opcodes.PUTFIELD, newClassName, 'arg', 'J')
	--		return;
	init:visitInsn(Opcodes.RETURN)
	--		max stacks
	-- 		# locals == 5 for 'this', arg #1 == long == 2 slots, arg #2 == long == 2 slots
	init:visitMaxs(3, 5)
	--	}
	init:visitEnd()

	--	public void run()
	local run = cw:visitMethod(Opcodes.ACC_PUBLIC, 'run', '()V', nil, nil)
	--	{
	run:visitCode()
	--	runNative(funcptr, arg):
	--		push 'this'
	run:visitVarInsn(Opcodes.ALOAD, 0);
	--		replace with 'this.funcptr'
	run:visitFieldInsn(Opcodes.GETFIELD, newClassName, 'funcptr', 'J')
	--		push 'this'
	run:visitVarInsn(Opcodes.ALOAD, 0);
	--		replace with 'this.arg'
	run:visitFieldInsn(Opcodes.GETFIELD, newClassName, 'arg', 'J')
	--		call 'runNative' with 2 args on the stack, returning 0 args
	run:visitMethodInsn(Opcodes.INVOKESTATIC, newClassName, 'runNative', '(JJ)V', false)
	--		return;
	run:visitInsn(Opcodes.RETURN)
	--		max stacks, locals
	run:visitMaxs(0, 0)
	--	}
	run:visitEnd()

	-- public static native long runNative(long funcptr, long arg);
	cw:visitMethod(bit.bor(Opcodes.ACC_NATIVE, Opcodes.ACC_PUBLIC, Opcodes.ACC_STATIC), 'runNative', '(JJ)V', nil, nil)
		:visitEnd()

	--}
	cw:visitEnd()

	local code = cw:toByteArray()
	local dynamicNativeRunnableClassObj = require 'java.tests.bytecodetoclass'
		.URIClassLoader(J, code, newClassName)

	return dynamicNativeRunnableClassObj 
end
