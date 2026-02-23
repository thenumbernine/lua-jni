/*
compile with javac -cp byte-buddy-1.18.5.jar TestByteBuddy.java
run with java -cp byte-buddy-1.18.5.jar:. TestByteBuddy

Next ByteBuddy test, so long as I'm on Java 21 and can't use Java 22's FFI i mean FFM...
Try to get our dynamically-created class to do what NativeRunnable does:

This is difficult because the docs on https://bytebuddy.net are down.
All I find is tuts, and the methods are vague.
Everyone says JavaASM is more difficult than ByteBuddy, 
but I have a feeling its simpler and just more lower-level which scares most people off.
*/
import java.lang.reflect.Modifier;
import net.bytebuddy.ByteBuddy;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.implementation.FixedValue;
import net.bytebuddy.description.modifier.Visibility;

public class TestByteBuddyNative {
	public static void main(String[] args) throws Exception {
/*			
		Class<?> dynamicType = new ByteBuddy()
			.<Runnable>subclass(Runnable.class)

			.two long fields
			.constructor with two long arguments
			.store the two fields

			.defineMethod("runNative", void.class, Visibility.PUBLIC)
				.withoutCode()
				.intercept(MethodDelegation.to(NativeBridge.class))
				//.attribute(net.bytebuddy.description.type.TypeDescription.ForLoadedType.of(Method.class).getDeclaredMethod("getModifiers"))
				//.modifier(Modifier.NATIVE)

			.invokable(isTypeInitializer()) // Target the static initializer
				. make it call System.loadLibrary("io_github_thenumbernine_NativeRunnable")

			.method(ElementMatchers.named("run"))
				.intercept(call the runNative function)

			.make()
			.load(Runnable.class.getClassLoader())
			.getLoaded();
		try {
			Runnable r = dynamicType.getDeclaredConstructor().newInstance(
				0,
				0
			);
			r.run();
		} catch (Exception e) {
		}
*/	

		Class<?> dynamicType = new ByteBuddy()
			.subclass(Object.class)
			.implement(Runnable.class)

			.defineField("funcptr", long.class, Modifier.PUBLIC)
			.defineField("arg", long.class, Modifier.PUBLIC)

			.method(ElementMatchers.named("toString"))
				.intercept(FixedValue.value("Hello World!"))

			// how does this work?
			.method(ElementMatchers.named("run"))
				.intercept(FixedValue.value("Hello World!"))

/* how to make a static native method?
            // A more robust way to define a method with specific modifiers:
            .defineMethod("anotherNativeMethod", long.class, Visibility.PUBLIC, Ownership.STATIC)
				.intercept(new net.bytebuddy.implementation.StubMethod())
				.attribute(new net.bytebuddy.description.modifier.ModifierContributor.ForMethod(Modifier.NATIVE))
*/
			.make()
			.load(Object.class.getClassLoader())
			.getLoaded();
		Runnable o = (Runnable)dynamicType.getDeclaredConstructor().newInstance();
		o.run();
	}
}

