package io.github.thenumbernine;

public class NativeRunnable implements java.lang.Runnable {
	// YES THE FIELDS ARE PUBLIC
	// GET OVER YOURSELF JAVA
	public long funcptr, arg;	//bitness of the systems ... is there 128-bit addressing anywhere?

	public NativeRunnable(long funcptr, long arg) {
		this.funcptr = funcptr;
		this.arg = arg;
	}

	// this is our Runnable interface, and Runnable has not results, so this has no result
	public void run() {
		NativeCallback.run(funcptr, arg);
	}
}
