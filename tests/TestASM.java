/*
compile with javac -cp asm-9.9.1.jar TestASM.java
run with java -cp asm-9.9.1.jar:. TestASM

ByteBuddy is difficult because the docs on https://bytebuddy.net are down.
All I find is tuts, and the methods are vague.
Everyone says JavaASM is more difficult than ByteBuddy, 
but I have a feeling its simpler and just more lower-level which scares most people off.

welp ASM was more straightforward, 
but it just leaves you with a byte array and says "good luck"
and to load that? you need to make a subclass as well.
maybe I can use ASM to make the subclass? 
oh wait then i'd be left with another byte array.
and no way to load it without continuing on forever.
*/

import org.objectweb.asm.ClassWriter;
import org.objectweb.asm.Opcodes;
import org.objectweb.asm.MethodVisitor;

import org.objectweb.asm.ClassWriter;
import org.objectweb.asm.MethodVisitor;
import org.objectweb.asm.Opcodes;

//class TestASMDynamicGenerator implements Opcodes {}

public class TestASM {
	public static void main(String[] args) throws Exception {
		
		// 1. Initialize ClassWriter to automatically compute stack size and local variables
		ClassWriter cw = new ClassWriter(ClassWriter.COMPUTE_FRAMES);

		// 2. Define the class: public class HelloWorld extends java.lang.Object
		cw.visit(Opcodes.V1_8, Opcodes.ACC_PUBLIC, "HelloWorld", null, "java/lang/Object", null);

		// 3. Create a default constructor (required for any class)
		MethodVisitor init = cw.visitMethod(Opcodes.ACC_PUBLIC, "<init>", "()V", null, null);
		init.visitCode();
		init.visitVarInsn(Opcodes.ALOAD, 0); // Load 'this'
		init.visitMethodInsn(Opcodes.INVOKESPECIAL, "java/lang/Object", "<init>", "()V", false);
		init.visitInsn(Opcodes.RETURN);
		init.visitMaxs(0, 0);
		init.visitEnd();

		// 4. Create the 'public static void main(String[] args)' method
		MethodVisitor mv = cw.visitMethod(Opcodes.ACC_PUBLIC + Opcodes.ACC_STATIC, "main", "([Ljava/lang/String;)V", null, null);
		mv.visitCode();

		// System.out.println("Hello World!");
		mv.visitFieldInsn(Opcodes.GETSTATIC, "java/lang/System", "out", "Ljava/io/PrintStream;");
		mv.visitLdcInsn("Hello World!");
		mv.visitMethodInsn(Opcodes.INVOKEVIRTUAL, "java/io/PrintStream", "println", "(Ljava/lang/String;)V", false);

		mv.visitInsn(Opcodes.RETURN);
		mv.visitMaxs(0, 0); // Values are ignored due to COMPUTE_FRAMES flag
		mv.visitEnd();

		cw.visitEnd();
		byte[] code = cw.toByteArray(); // Return the bytecode as a byte array

		Class<?> helloWorldClass = java.lang.invoke.MethodHandles.lookup().defineClass(code);

		// Invoke the main method via reflection
		helloWorldClass
			.getMethod("main", String[].class)
			.invoke(null, (Object) new String[0]);
	}
}
