public class TestNative {
	public TestNative() { ctorFwdMethod_1(); }
	public TestNative(Object o) { ctorFwdMethod_2(o); }
	public TestNative(int a) { ctorFwdMethod_3(a); }
	public TestNative(int a, double b) { ctorFwdMethod_4(a,b); }
	public TestNative(double a, int b) { ctorFwdMethod_5(a,b); }

	private native void ctorFwdMethod_1();
	private native void ctorFwdMethod_2(Object o);
	private native void ctorFwdMethod_3(int a);
	private native void ctorFwdMethod_4(int a, double b);
	private native void ctorFwdMethod_5(double a, int b);

	// interesting fact, for .dex, initialized value fields are converted into asm code inserted into the ctor ...
	public String foo;// = "bar";
	public int bar;// = 1;
	public double baz;// = 2;

	public native static String test();
	public native String ol(long a);
	public native String ol(boolean a);
	public native String ol(short a);
	public native String ol(int a);
	public native String ol(float a);
	public native String ol(double b);
	public native String ol(String c);
	public native String ol(Object d);
	public native String ol(char[] e);

	public native void foo(int a);
	public native void foo(Object a, int b);
	public native void foo(Object a, double b);
	public native void foo(double a, Object b);

	public native int getCount();
	public native Object getItem(int i);
	public native long getItemId(int i);
	public native Object getView(int i, Object view, Object group);
}
