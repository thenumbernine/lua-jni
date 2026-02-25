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

/* google ai gives this tip at the bottom of the page */
		Class<?> helloWorldClass = java.lang.invoke.MethodHandles.lookup().defineClass(code);
/**/
/* works but does require a dynamic subclass what I need to avoid... * /
		// 1. Create a loader that exposes the protected defineClass method
		class ByteArrayClassLoader extends ClassLoader {
			public Class<?> define(String name, byte[] b) {
				return defineClass(name, b, 0, b.length);
			}
		}

		ByteArrayClassLoader loader = new ByteArrayClassLoader();
		
		// 2. Use define() instead of loadClass() to register the bytes
		Class<?> helloWorldClass = loader.define("HelloWorld", code);
/**/
/* doesn't work, ClassNotFound, and also is a subclass I want to avoid... 
maybe doesn't work cuz defineClass is protected?
can these anonymous subclasses call protected functions?
* /
		
		// Custom ClassLoader to define the class from bytes
		ClassLoader loader = new ClassLoader() {
			public Class<?> define(String name, byte[] b) {
				return defineClass(name, b, 0, b.length);
			}
		};

		Class<?> helloWorldClass = loader.define("HelloWorld", code); // Use custom loader logic here
		// (Simplified for example; in practice, use the loader's define method)
/**/
/* try #3 ... not gonna work * /
		//ClassLoader loader = new ClassLoader();	// but it's abstract ... smh fucking hate java
		ClassLoader loader = Object.class.getClassLoader();
		Class<?> helloWorldClass = loader.defineClass("HelloWorld", code, 0, code.length);
/**/

		// Invoke the main method via reflection
		helloWorldClass
			.getMethod("main", String[].class)
			.invoke(null, (Object) new String[0]);
	}
}
