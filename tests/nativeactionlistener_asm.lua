--[[
java.awt.event.ActionListener implementation
that forwards to io.github.thenumbernine.NativeRunnable
dynamically generated using ASM 
--]]
local M = {}
function M:run(J, jsuperclass)
	if M.cache then return M.cache end

	jsuperclass = jsuperclass or 'java/lang/Object'

	-- how about separate the NativeCallback static native method & System.load into its own class ...
	local NativeCallback = require 'java.tests.nativecallback_asm'(J)

	local ClassWriter = J.org.objectweb.asm.ClassWriter
	assert(require 'java.class':isa(ClassWriter), "JRE isn't finding ASM")
	local cw = ClassWriter(ClassWriter.COMPUTE_FRAMES)

	local Opcodes = J.org.objectweb.asm.Opcodes

	-- can I make this use the same namespace as my previously built .so? yes.
	--public class NativeActionListener extends java.lang.Object {
	local newClassName = 'io/github/thenumbernine/NativeActionListener'
	cw:visit(
		Opcodes.V1_6,
		Opcodes.ACC_PUBLIC,
		newClassName,
		nil,
		jsuperclass,
		J:_newArray(J.String, 1, J:_str'java/awt/event/ActionListener'))

	--	long funcptr;
	cw:visitField(Opcodes.ACC_PUBLIC, 'funcptr', 'J', nil, nil)
		:visitEnd()

	--	public NativeActionListener(long funcptr, long arg)
	local init = cw:visitMethod(Opcodes.ACC_PUBLIC, '<init>', '(J)V', nil, nil)
	--	{
	init:visitCode()
	--		push 'this'
	init:visitVarInsn(Opcodes.ALOAD, 0)
	--		call super() aka java.lang.Object();
	init:visitMethodInsn(Opcodes.INVOKESPECIAL, jsuperclass, '<init>', '()V', false)
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

	--	public void actionPerformed(ActionEvent e)
	local run = cw:visitMethod(Opcodes.ACC_PUBLIC, 'actionPerformed', '(Ljava/awt/event/ActionEvent;)V', nil, nil)
	--	{
	run:visitCode()
	--	NativeCallback.run(funcptr, arg):
	--		push 'this'
	run:visitVarInsn(Opcodes.ALOAD, 0);
	--		replace with 'this.funcptr'
	run:visitFieldInsn(Opcodes.GETFIELD, newClassName, 'funcptr', 'J')
	--		push 'e'
	run:visitVarInsn(Opcodes.ALOAD, 1);
	--		call 'run'
	run:visitMethodInsn(
		Opcodes.INVOKESTATIC,
		NativeCallback._classpath:gsub('%.', '/'),
		'run',
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

	M.cache = (J:_getClassForJClass(classAsObj._ptr))
	return M.cache
end
setmetatable(M, {
	__call = M.run,
})
return M
