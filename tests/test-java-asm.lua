#!/usr/bin/env luajit

-- Same as TestASM but with luajit
-- still depends on asm.jar though
-- Next would be to run the contents of asm.jar in LuaJIT as well.

local ffi = require 'ffi'
local J = require 'java.vm'{
	optionList = {
		--[[ but it wont init with this ...
		'--add-opens',	-- without this, when running pure-JNI created JVM, it will choke on MethodHandles:lookup()
		--]]
	},
	props = {
		['java.class.path'] = table.concat({
			'asm-9.9.1.jar',
			'.',
		}, ':'),
	},
}.jniEnv

local ClassWriter = J.org.objectweb.asm.ClassWriter
assert(require 'java.class':isa(ClassWriter), "JRE isn't finding ASM")
local cw = ClassWriter(ClassWriter.COMPUTE_FRAMES)

local newClassName = 'HelloWorld'
local Opcodes = J.org.objectweb.asm.Opcodes

--public class HelloWorld extends java.lang.Object {
cw:visit(Opcodes.V1_8, Opcodes.ACC_PUBLIC, newClassName, nil, 'java/lang/Object', nil)

--	public HelloWorld()
local init = cw:visitMethod(Opcodes.ACC_PUBLIC, '<init>', '()V', nil, nil)

--	{
init:visitCode()

--		java.lang.Object();
init:visitVarInsn(Opcodes.ALOAD, 0)
init:visitMethodInsn(Opcodes.INVOKESPECIAL, 'java/lang/Object', '<init>', '()V', false)

--		return;
init:visitInsn(Opcodes.RETURN)
init:visitMaxs(0, 0)

--	}
init:visitEnd()

--	public static void main(String[] args)
local mv = cw:visitMethod(Opcodes.ACC_PUBLIC + Opcodes.ACC_STATIC, 'main', '([Ljava/lang/String;)V', nil, nil)

--	{
mv:visitCode()

-- 		System.out.println('Hello World!');
mv:visitFieldInsn(Opcodes.GETSTATIC, 'java/lang/System', 'out', 'Ljava/io/PrintStream;')
mv:visitLdcInsn('Hello World!')
mv:visitMethodInsn(Opcodes.INVOKEVIRTUAL, 'java/io/PrintStream', 'println', '(Ljava/lang/String;)V', false)

--		return;
mv:visitInsn(Opcodes.RETURN)
mv:visitMaxs(0, 0)
--	}
mv:visitEnd()

--}
cw:visitEnd()

local code = cw:toByteArray()
local helloWorldClass = require 'java.tests.bytecodetoclass'
	.URIClassLoader(J, code, newClassName)
helloWorldClass
	:getMethod('main', J.String.class:arrayType())
	:invoke(nil, J:_newArray(J.String, 0))
