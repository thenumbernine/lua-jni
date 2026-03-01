package io.github.thenumbernine;

public class NativeRunnable implements java.lang.Runnable {
	public long funcptr;	//bitness of the systems ... is there 128-bit addressing anywhere?
	public Object arg;
	
	public NativeRunnable(long funcptr) {
		this.funcptr = funcptr;
	}

	public NativeRunnable(long funcptr, Object arg) {
		this.funcptr = funcptr;
		this.arg = arg;
	}

	// this is our Runnable interface, and Runnable has not results, so this has no result
	public void run() {
		NativeCallback.run(funcptr, arg);
	}
}
