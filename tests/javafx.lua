#!/usr/bin/env luajit
--[[
so when going from javax.swing to javafx.*
... Java added the required constraint extra module cmdline cfg crap
... and Java added the required constraint of subclassing a class just to make an app
.. so it's double the headache,
and until I do something like bytecode injection to build classes at runtime...
... this demo won't get finished.

--]]

local J = require 'java.vm'{
	options = {
		['--module-path'] = '/usr/share/openjfx/lib',
		['--add-modules'] = 'javafx.controls,javafx.fxml',
	},
	props = {
		['java.class.path'] = table.concat({
			'asm-9.9.1.jar',		-- needed for ASM
			'.',
		}, ':'),
		--['java.library.path'] = '.',
	}
}.jniEnv

--[[
How to build a JavaFX app without subclassing anything ...
it is possible with Swing up to the exception of making your own Runnable (hence NativeRunnable)
... probably not.
you'd probably need a Application subclass , then do ...

I could do this with ASM ...
I currently need a layer on it for converting Java<->Lua
especially for passing in ActionListener events to Lua
and javafx.Application javafx.stage.Stage's
maybe I could use the java.jnienv Lua class's translation for that ...
Then how to get the vararg Java objects to jobjects before calling into C? (since I don't want to make multiple stub codes ...
One fix is to replace the JNI arg with a jobject that points to an Object[] that the LuaJIT side has to decode...
Then the Java code would call io.github.thenumbernine.NativeCallback.run(long closureAddr, Object[]{args...})
(but this but in Java-ASM calls...)
--]]

local ThisApplication
do
	local NativeCallback = require 'java.tests.nativecallback_asm'(J)

	local ClassWriter = J.org.objectweb.asm.ClassWriter
	assert(require 'java.class':isa(ClassWriter), "JRE isn't finding ASM")
	local cw = ClassWriter(ClassWriter.COMPUTE_FRAMES)

	local Opcodes = J.org.objectweb.asm.Opcodes

	-- public class ThisApplication {
	local classname = 'io/github/thenumbernine/ThisApplication'
	local superclassname = 'javafx/application/Application'
	cw:visit(
		Opcodes.V1_6,
		Opcodes.ACC_PUBLIC,
		classname,
		nil,
		superclassname,
		nil)

	--	public static long funcptr;
	cw:visitField(bit.bor(Opcodes.ACC_PUBLIC, Opcodes.ACC_STATIC), 'funcptr', 'J', nil, nil)
		:visitEnd()

	--	public <init>() { super(); }
	local init = cw:visitMethod(Opcodes.ACC_PUBLIC, '<init>', '()V', nil, nil)
	init:visitCode()
	init:visitVarInsn(Opcodes.ALOAD, 0)
	init:visitMethodInsn(Opcodes.INVOKESPECIAL, superclassname, '<init>', '()V', false)
	init:visitInsn(Opcodes.RETURN)
	init:visitMaxs(0, 0)
	init:visitEnd()

	-- public void start(javafx.stage.Stage stage) { NativeCallback.run(funcptr, stage); }
	local run = cw:visitMethod(Opcodes.ACC_PUBLIC, 'start', '(Ljavafx/stage/Stage;)V', nil, nil)
	run:visitCode()
	run:visitFieldInsn(Opcodes.GETSTATIC, classname, 'funcptr', 'J')
	run:visitVarInsn(Opcodes.ALOAD, 1);
	run:visitMethodInsn(
		Opcodes.INVOKESTATIC,
		NativeCallback._classpath:gsub('%.', '/'),
		'run', '(JLjava/lang/Object;)Ljava/lang/Object;',
		false)
	run:visitInsn(Opcodes.RETURN)
	run:visitMaxs(0, 0)
	run:visitEnd()

	local classObj = require 'java.tests.bytecodetoclass'(J, cw:toByteArray(), classname)
	ThisApplication = J:_getClassForJClass(classObj._ptr)
end


local ffi = require 'ffi'
callback = function(stage)
	stage = J:_javaToLuaArg(stage, 'javafx.stage.Stage')

	stage:setTitle'Hello World!'

	local btn = J.javafx.scene.control.Button
	btn:setText'Button 1'

	local root = J.javafx.scene.layout.StackPane()
	root:getChildren():add(btn)
	stage:setScene(
		J.javafx.scene.Scene(root, 300, 250)
	)
	stage:show()
end
closure = ffi.cast('jobject (*)(jobject)', callback)
print('closure', closure)
local closureLong = ffi.cast('jlong', closure)
print('closureLong', ('0x%x'):format(tonumber(closureLong)))
ThisApplication.funcptr = closureLong
print('ThisApplication.funcptr', ('0x%x'):format(tonumber(ThisApplication.funcptr)))
-- TODO even if I write ThisApplication.funcptr here, within ThisApplication.launch it is still zero...

--ThisApplication:launch()	-- "JVM java.lang.RuntimeException: Error: unable to determine Application class"
--ThisApplication:launch(ThisApplication.class)
ThisApplication:launch(ThisApplication.class)
