package io.github.thenumbernine;

public class NativeRunnable implements java.lang.Runnable {
    static {
		System.loadLibrary("io_github_thenumbernine_NativeRunnable");
	}

	// this is a wrapper for what should be an underlying pthread-style callback,
	// i.e. void*(*)(void*)
	// i.e. void *callback(void*) {}
	public static native long runNative(long funcptr, long arg);

	// YES THE FIELDS ARE PUBLIC
	// GET OVER YOURSELF JAVA
	public long funcptr, arg;	//bitness of the systems ... is there 128-bit addressing anywhere?

	public NativeRunnable(long funcptr) {
		this(funcptr, 0);
	}

	public NativeRunnable(long funcptr, long arg) {
		this.funcptr = funcptr;
		this.arg = arg;
	}

	// this is our Runnable interface, and Runnable has not results, so this has no result
	public void run() {
		runNative(funcptr, arg);
	}
}
