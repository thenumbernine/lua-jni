class TestNativeRunnable implements java.lang.Runnable {
    static { System.loadLibrary("runnable_lib"); }
	long funcptr, arg;	//bitness of the systems ... is there 128-bit addressing anywhere?
	public TestNativeRunnable(long funcptr) { this(funcptr, 0); }
	public TestNativeRunnable(long funcptr, long arg) { this.funcptr = funcptr; this.arg = arg; }

	// this is our Runnable interface, and Runnable has not results, so this has no result
	public void run() { runNative(funcptr, arg); }

	// this is a wrapper for what should be an underlying pthread-style callback,
	// i.e. void*(*)(void*)
	// i.e. void *callback(void*) {}
	public native long runNative(long funcptr, long arg);
}
