class Runnable implements java.lang.Runnable {
    static {
        System.loadLibrary("runnable_lib");
    }

	public void run() { runNative(); }
	public static native void runNative();
}
