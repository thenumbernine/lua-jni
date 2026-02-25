#!/usr/bin/env luajit

-- runnable.lua but using Java-ASM instead of an external Runnable subclass
-- (The last hurdle is it still needs some external source to load the Java-ASM bytecode, which at least requires a file-write, or at worse requires a subclass of its own.)
local path = require 'ext.path'

local J = require 'java.vm'{
	props = {
		['java.class.path'] = table.concat({
			'.',
			'asm-9.9.1.jar',
		}, ':'),
		['java.library.path'] = '.',
	},
}.jniEnv

require 'java.build'.C{
	src = 'DynamicNativeRunnable.c',
	dst = 'libDynamicNativeRunnable.so',
}

-- I think Java needs this to be in a class's static{} block...
-- otherwise it doesnt seem to load successfully
--J.System:loadLibrary'DynamicNativeRunnable'
--J.System:loadLibrary'libDynamicNativeRunnable.so'
--J.System:loadLibrary'io_github_thenumbernine_NativeRunnable'

local dynamicNativeRunnableClassObj
do
	local ClassWriter = J.org.objectweb.asm.ClassWriter
	assert(require 'java.class':isa(ClassWriter), "JRE isn't finding ASM")
	local cw = ClassWriter(ClassWriter.COMPUTE_FRAMES)

	local newClassName = 'DynamicNativeRunnable'
	local Opcodes = J.org.objectweb.asm.Opcodes

	--public class DynamicNativeRunnable extends java.lang.Object {
	cw:visit(Opcodes.V1_8, Opcodes.ACC_PUBLIC, newClassName, nil, 'java/lang/Object', nil)

	-- TODO: or can I do that myself before even invoking cw? I think not.
	--	static
	local mv = cw:visitMethod(Opcodes.ACC_STATIC, '<clinit>', '()V', nil, nil)
	--	{
	mv:visitCode()
	--	push "DynamicNativeRunnable"	-- "JVM java.lang.UnsatisfiedLinkError: Expecting an absolute path of the library: ./libDynamicNativeRunnable.so"
	mv:visitLdcInsn((path:cwd()/'libDynamicNativeRunnable.so').path)
	--	call System.loadLibrary
	mv:visitMethodInsn(Opcodes.INVOKESTATIC, 'java/lang/System', 'load', '(Ljava/lang/String;)V', false)
	--	return
	mv:visitInsn(Opcodes.RETURN)
	--	max stacks, locals
	mv:visitMaxs(1, 0)
	--	}
	mv:visitEnd()

	--	long funcptr;
	cw:visitField(Opcodes.ACC_PUBLIC, 'funcptr', 'J', nil, nil)
		:visitEnd()

	-- long arg;
	cw:visitField(Opcodes.ACC_PUBLIC, 'arg', 'J', nil, nil)
		:visitEnd()

	--	public DynamicNativeRunnable()
	local init = cw:visitMethod(Opcodes.ACC_PUBLIC, '<init>', '()V', nil, nil)
	--	{
	init:visitCode()
	--		java.lang.Object();
	init:visitVarInsn(Opcodes.ALOAD, 0)
	init:visitMethodInsn(Opcodes.INVOKESPECIAL, 'java/lang/Object', '<init>', '()V', false)
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
	dynamicNativeRunnableClassObj = require 'java.tests.bytecodetoclass'(J, code, newClassName)
end

callback = function(arg)
	print('hello from within Lua, arg', arg)
end
local ffi = require 'ffi'
closure = ffi.cast('void *(*)(void*)', callback)

local nativeRunnable = dynamicNativeRunnableClassObj:getDeclaredConstructor():newInstance()
nativeRunnable.funcptr = ffi.cast('int64_t', closure) 
nativeRunnable.arg = ffi.cast('int64_t', 1234567)
print('nativeRunnable.funcptr', nativeRunnable.funcptr)
print('nativeRunnable.arg', nativeRunnable.arg)
nativeRunnable:run()
