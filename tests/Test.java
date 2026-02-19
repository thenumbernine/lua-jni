public class Test {
	public Test() {
		System.out.println("Test:Test()");
	}

	public String foo = "bar";

	public int bar = 1;

	public double baz = 2;

	public static String test() { return "Testing"; }

	public String ol(long a) { return "ol_long"; }
	public String ol(boolean a) { return "ol_boolean"; }
	public String ol(short a) { return "ol_short"; }
	public String ol(int a) { return "ol_int"; }
	public String ol(float a) { return "ol_float"; }
	public String ol(double b) { return "ol_double"; }
	public String ol(String c) { return "ol_String"; }
	public String ol(Object d) { return "ol_Object"; }
	public String ol(char[] e) { return "ol_char_array"; }
}
