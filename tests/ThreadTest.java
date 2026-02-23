public class ThreadTest {
	public static void main(String[] args) throws InterruptedException {
		Thread thread = new Thread(new Runnable() {
			public void run() {
				System.out.println("in thread");
			}
		});
		thread.start();
		thread.join();
		System.out.println("out of thread, done");
	}
}
