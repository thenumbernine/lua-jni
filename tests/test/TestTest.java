public class TestTest {
	public static void main(String[] args) {
		Test test = new Test();
		test.test();
		System.out.println("foo "+test.foo);
		System.out.println("bar "+test.bar);
		System.out.println("baz "+test.baz);
		System.out.println("long "+test.ol((long)1));
		System.out.println("boolean "+test.ol(true));
		System.out.println("short "+test.ol((short)1));
		System.out.println("int "+test.ol((int)1));
		System.out.println("float "+test.ol((float)1));
		System.out.println("double "+test.ol((double)1));
		System.out.println("String "+test.ol(""));
		System.out.println("Object "+test.ol(new Object()));
		System.out.println("char[] "+test.ol(new char[]{}));
	}
}
