// how is a swing test app supposed to look?

import javax.swing.JFrame;
import javax.swing.JLabel;
import javax.swing.SwingUtilities;

public class TestSwing implements Runnable {
	public void run() {
		JFrame frame = new JFrame("HelloWorldSwing Example");
		frame.setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);

		JLabel label = new JLabel("Hello World!");
		frame.add(label);

		// you need to call one or the other, or else the frame doesn't show
		frame.setSize(300, 200);
		//frame.pack();

		frame.setLocationRelativeTo(null);
		frame.setVisible(true);
	}

	public static void main(String[] args) {
		SwingUtilities.invokeLater(new TestSwing());
	}
}
