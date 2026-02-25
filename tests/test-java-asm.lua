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

local Opcodes = J.org.objectweb.asm.Opcodes
cw:visit(Opcodes.V1_8, Opcodes.ACC_PUBLIC, 'HelloWorld', nil, 'java/lang/Object', nil)

local init = cw:visitMethod(Opcodes.ACC_PUBLIC, '<init>', '()V', nil, nil)
init:visitCode()
init:visitVarInsn(Opcodes.ALOAD, 0)
init:visitMethodInsn(Opcodes.INVOKESPECIAL, 'java/lang/Object', '<init>', '()V', false)
init:visitInsn(Opcodes.RETURN)
init:visitMaxs(0, 0)
init:visitEnd()

local mv = cw:visitMethod(Opcodes.ACC_PUBLIC + Opcodes.ACC_STATIC, 'main', '([Ljava/lang/String;)V', nil, nil)
mv:visitCode()

-- System.out.println('Hello World!')
mv:visitFieldInsn(Opcodes.GETSTATIC, 'java/lang/System', 'out', 'Ljava/io/PrintStream;')
mv:visitLdcInsn('Hello World!')
mv:visitMethodInsn(Opcodes.INVOKEVIRTUAL, 'java/io/PrintStream', 'println', '(Ljava/lang/String;)V', false)

mv:visitInsn(Opcodes.RETURN)
mv:visitMaxs(0, 0)
mv:visitEnd()

cw:visitEnd()
local code = cw:toByteArray()

local MethodHandles = J.java.lang.invoke.MethodHandles
print('MethodHandles', MethodHandles)
--[[
local lookup = MethodHandles:lookup()	-- "JVM java.lang.IllegalCallerException: no caller frame"
local helloWorldClass = lookup:defineClass(code)
--]]
--[[ upon "defineClass", throws "JVM java.lang.IllegalAccessException: Lookup does not have PACKAGE access"
local lookup = MethodHandles:publicLookup()
local helloWorldClass = lookup:defineClass(code)
--]]
--[[
local publicLookup = MethodHandles:publicLookup()
--local lookup = publicLookup['in'](publicLookup, ClassWriter:_class())	-- upon :defineClass(), "JVM java.lang.IllegalAccessException: Lookup does not have PACKAGE access"
local lookup = publicLookup['in'](publicLookup, J.Object:_class())	--  upon :defineClass(), "JVM java.lang.IllegalAccessException: Lookup does not have PACKAGE access"
local helloWorldClass = lookup:defineClass(code)
--]]
--[[
local publicLookup = MethodHandles:publicLookup()
local lookup = MethodHandles:privateLookupIn(ClassWriter:_class(), publicLookup)	-- "JVM java.lang.IllegalAccessException: caller does not have PRIVATE and MODULE lookup mode"
local helloWorldClass = lookup:defineClass(code)
--]]
--[[
local publicLookup = MethodHandles:publicLookup()
local helloWorldClass = publicLookup:defineHiddenClass(code, true)	-- "JVM java.lang.IllegalAccessException: java.lang.Object/publicLookup does not have full privilege access"
--local helloWorldClass = publicLookup:defineHiddenClass(code, false)	-- "JVM java.lang.IllegalAccessException: java.lang.Object/publicLookup does not have full privilege access"
--]]
-- [[ this works but it relies, once again, on an external class. smh i hate java.
require 'java.build'.java{
	src = 'TestLookupFactory.java',
	dst = 'TestLookupFactory.class',
}
assert(require 'java.class':isa(J.TestLookupFactory))
local lookup = J.TestLookupFactory:getFullAccess()
local helloWorldClass = lookup:defineClass(code)
--]]
--[[ https://stackoverflow.com/questions/31226170/load-asm-generated-class-while-runtime
-- still needs a custom subclass to be compiled ...
print(J.Class:getClassLoader())
print(J.Class:_class():getClassLoader())
print(J.Class:getClass():getClassLoader())
print(J.Thread:currentThread())
local loader = J.Thread:currentThread():getContextClassLoader()
print('loader', loader)
local helloWorldClass = loader:defineClass('HelloWorld', code, 0, #code)
print('helloWorldClass', helloWorldClass)
os.exit()
--]]
-- [[ some say URLClassLoader, but that requires file write?
-- https://stackoverflow.com/a/1874179/2714073
--]]

helloWorldClass
	:getMethod('main', J.String:_class():arrayType())
	:invoke(nil, J:_newArray(J.String, 0))
