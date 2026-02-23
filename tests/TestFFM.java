// I guess this is for Java 22, but I'm only using OpenJDK at Java 21, so I'll just leave this here ...
import java.lang.foreign.*;
import java.lang.invoke.MethodHandle;
import java.nio.charset.StandardCharsets;

class TestFFM {
	public static void main(String[] args) {

		String javaString = "Hello FFM API!";

		Linker linker = Linker.nativeLinker();
		SymbolLookup stdlib = linker.defaultLookup();

		MemorySegment strlenAddress = stdlib.find("strlen").orElseThrow();

		FunctionDescriptor signature = FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS);

		MethodHandle strlen = linker.downcallHandle(strlenAddress, signature);

		try (Arena offHeap = Arena.ofConfined()) {
			MemorySegment cString = offHeap.allocateFrom(StandardCharsets.UTF_8, javaString);

			long len = (long) strlen.invokeExact(cString);

			System.out.println("Original Java String: \"" + javaString + "\"");
			System.out.println("Length calculated by C strlen(): " + len);
			System.out.println("Length calculated by Java String.length(): " + javaString.length());
		}
	}
}
