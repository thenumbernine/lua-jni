/* 
I guess this is for Java 22, but I'm only using OpenJDK at Java 21, so I'll just leave this here ...
Oh wait, it is available in Java 21.
Compile with: javac --release 21 --enable-preview TestFFM.java
Run with: java --enable-preview TestFFM
*/
import java.lang.foreign.*;
import java.lang.invoke.MethodHandle;
import java.nio.charset.StandardCharsets;

class TestFFM {
	public static void main(String[] args) throws Throwable {
		// test of calling libc's strlen

		String javaString = "Hello FFM API!";

		Linker linker = Linker.nativeLinker();
		SymbolLookup libC = linker.defaultLookup();

		MemorySegment strlenAddress = libC.find("strlen").orElseThrow();

		FunctionDescriptor signature = FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS);

		MethodHandle strlen = linker.downcallHandle(strlenAddress, signature);

		try (Arena offHeap = Arena.ofConfined()) {
			//MemorySegment cString = offHeap.allocateFrom(StandardCharsets.UTF_8, javaString);	//not availabe in Java 21
			MemorySegment cString = offHeap.allocate(javaString.length()+1, 1);
			for (int i = 0; i < javaString.length(); ++i) {
				cString.set(ValueLayout.JAVA_BYTE, i, (byte)javaString.charAt(i));
			}

			long len = (long)strlen.invokeExact(cString);

			System.out.println("Original Java String: \"" + javaString + "\"");
			System.out.println("Length calculated by C strlen(): " + len);
			System.out.println("Length calculated by Java String.length(): " + javaString.length());
		}
	}
}
