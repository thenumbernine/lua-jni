package io.github.thenumbernine;

public class NativeCallback {
    static {
		System.loadLibrary("io_github_thenumbernine_NativeCallback");
	}

	// this is a wrapper for what should be an underlying pthread-style callback,
	// i.e. void*(*)(void*)
	// i.e. void *callback(void*) {}
	public static native Object run(long funcptr, Object arg);
}
