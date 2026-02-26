--[[
This is the equivalent of ./io/github/thenumbernine/NativeRunnable.java
This at least offloads the .java->.class side of things to LuaJIT
But it still requires a separate .so
--]]
local M = {}
function M:run(J)
	if M.cache then return M.cache end

	-- how about separate the NativeCallback static native method & System.load into its own class ...
	local NativeCallback = require 'java.tests.nativecallback_asm'(J)

	local ClassWriter = J.org.objectweb.asm.ClassWriter
	assert(require 'java.class':isa(ClassWriter), "JRE isn't finding ASM")
	local cw = ClassWriter(ClassWriter.COMPUTE_FRAMES)

	local Opcodes = J.org.objectweb.asm.Opcodes

	-- can I make this use the same namespace as my previously built .so? yes.
	--public class NativeRunnable extends java.lang.Object {
	local newClassName = 'io/github/thenumbernine/NativeRunnable'
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
	cw:visitField(Opcodes.ACC_PUBLIC, 'arg', 'J', nil, nil)
		:visitEnd()

	--	public NativeRunnable(long funcptr, long arg)
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
	--	NativeCallback.run(funcptr, arg):
	--		push 'this'
	run:visitVarInsn(Opcodes.ALOAD, 0);
	--		replace with 'this.funcptr'
	run:visitFieldInsn(Opcodes.GETFIELD, newClassName, 'funcptr', 'J')
	--		push 'this'
	run:visitVarInsn(Opcodes.ALOAD, 0);
	--		replace with 'this.arg'
	run:visitFieldInsn(Opcodes.GETFIELD, newClassName, 'arg', 'J')
	--		call 'run' with 2 args on the stack, returning 0 args
	run:visitMethodInsn(Opcodes.INVOKESTATIC, NativeCallback._classpath:gsub('%.', '/'), 'run', '(JJ)V', false)
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

	M.cache = J:_getClassForJClass(classAsObj._ptr)
	return M.cache
end
setmetatable(M, {
	__call = M.run,
})
return M
