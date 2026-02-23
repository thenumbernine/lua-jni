// compile with javac -cp byte-buddy-1.18.5.jar TestByteBuddy.java
// run with java -cp byte-buddy-1.18.5.jar:. TestByteBuddy
import net.bytebuddy.ByteBuddy;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.implementation.FixedValue;
public class TestByteBuddy {
	public static void main(String[] args) {
		Class<java.lang.Object> _java_lang_Object = java.lang.Object.class;
		Class<?> dynamicType = new ByteBuddy()
			.<java.lang.Object>subclass(_java_lang_Object)
			.method(ElementMatchers.named("toString"))
			.intercept(FixedValue.value("Hello World!"))
			.make()
			.load(_java_lang_Object.getClassLoader())
			.getLoaded();
		try {
			System.out.println(dynamicType.getDeclaredConstructor().newInstance().toString());
		} catch (Exception e) {
		}
	}
}
