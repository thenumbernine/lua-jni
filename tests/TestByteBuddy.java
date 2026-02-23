// compile with javac -cp byte-buddy-1.18.5.jar TestByteBuddy.java
// run with java -cp byte-buddy-1.18.5.jar:. TestByteBuddy
import net.bytebuddy.ByteBuddy;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.implementation.FixedValue;
public class TestByteBuddy {
	public static void main(String[] args) {
		Class<?> dynamicType = new ByteBuddy()
			.subclass(Object.class)
			.method(ElementMatchers.named("toString"))
			.intercept(FixedValue.value("Hello World!"))
			.make()
			.load(Object.class.getClassLoader())
			.getLoaded();
		try {
			System.out.println(dynamicType.getDeclaredConstructor().newInstance().toString());
		} catch (Exception e) {
		}
	}
}
