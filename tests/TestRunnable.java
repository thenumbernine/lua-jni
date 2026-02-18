// this test class should do what the lua code is also doing: run the Runnable
public class TestRunnable {
	public static void main(String[] args) {
		// works
		//Runnable.runNative();
		// also works
		new Runnable().run();
	}
}
