--[[
This is the equivalent of ./io/github/thenumbernine/NativeRunnable.java
This at least offloads the .java->.class side of things to LuaJIT
But it still requires a separate .so
--]]
return function(J)
	-- how about separate the NativeCallback static native method & System.load into its own class ...
	-- [[ java-asm based
	local NativeCallback = require 'java.tests.nativecallback_asm'(J)
	--]]
	--[[ luajit java.classdata
	local NativeCallback = require 'java.tests.nativecallback_classdata'(J)
	--]]

	-- can I make this use the same namespace as my previously built .so? yes.
	local newClassName = 'io/github/thenumbernine/NativeRunnable'

	-- check if it's already loaded
	local cl = J:_findClass(newClassName)
	if cl then return cl end

	local ClassWriter = J.org.objectweb.asm.ClassWriter
	assert(require 'java.class':isa(ClassWriter), "JRE isn't finding ASM")
	local cw = ClassWriter(ClassWriter.COMPUTE_FRAMES)

	local Opcodes = J.org.objectweb.asm.Opcodes

	--public class NativeRunnable extends java.lang.Object {
	cw:visit(
		Opcodes.V1_6,
		Opcodes.ACC_PUBLIC,
		newClassName,
		nil,
		'java/lang/Object',
		J:_newArray(J.String, 1, J:_str'java/lang/Runnable'))

	--	long funcptr;
	cw:visitField(Opcodes.ACC_PUBLIC, 'funcptr', 'J', nil, nil)
		:visitEnd()

	-- long arg;
	cw:visitField(Opcodes.ACC_PUBLIC, 'arg', 'Ljava/lang/Object;', nil, nil)
		:visitEnd()

	--	public NativeRunnable(long funcptr)
	local init = cw:visitMethod(Opcodes.ACC_PUBLIC, '<init>', '(J)V', nil, nil)
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
	--		return;
	init:visitInsn(Opcodes.RETURN)
	--		max stacks, locals
	init:visitMaxs(0, 0)
	--	}
	init:visitEnd()

	--	public NativeRunnable(long funcptr, Object arg)
	local init = cw:visitMethod(Opcodes.ACC_PUBLIC, '<init>', '(JLjava/lang/Object;)V', nil, nil)
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
	init:visitVarInsn(Opcodes.ALOAD, 3)
	--		this.funcptr = arg #2
	init:visitFieldInsn(Opcodes.PUTFIELD, newClassName, 'arg', 'Ljava/lang/Object;')
	--		return;
	init:visitInsn(Opcodes.RETURN)
	--		max stacks, locals
	init:visitMaxs(0, 0)
	--	}
	init:visitEnd()

	--	public void run()
	local run = cw:visitMethod(Opcodes.ACC_PUBLIC, 'run', '()V', nil, nil)
	--	{
	run:visitCode()
	--	NativeCallback.run(funcptr, arg):
	--		push 'this'
	run:visitVarInsn(Opcodes.ALOAD, 0);
	--		replace with 'this.funcptr'
	run:visitFieldInsn(Opcodes.GETFIELD, newClassName, 'funcptr', 'J')
	--		push 'this'
	run:visitVarInsn(Opcodes.ALOAD, 0);
	--		replace with 'this.arg'
	run:visitFieldInsn(Opcodes.GETFIELD, newClassName, 'arg', 'Ljava/lang/Object;')
	--		call 'run' with 2 args on the stack, returning 0 args
	run:visitMethodInsn(
		Opcodes.INVOKESTATIC,
		NativeCallback._classpath:gsub('%.', '/'),
		assert(NativeCallback._runMethodName),
		'(JLjava/lang/Object;)Ljava/lang/Object;',
		false)
	--		return;
	run:visitInsn(Opcodes.RETURN)
	--		max stacks, locals
	run:visitMaxs(0, 0)
	--	}
	run:visitEnd()

	--}
	cw:visitEnd()

	local code = cw:toByteArray()

	-- create the java .class to go along with it
	local classAsObj = require 'java.tests.bytecodetoclass'(J, code, newClassName)

	return (J:_getClassForJClass(classAsObj._ptr))
end
