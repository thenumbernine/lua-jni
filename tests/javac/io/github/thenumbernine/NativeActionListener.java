package io.github.thenumbernine;
public class NativeActionListener implements java.awt.event.ActionListener {
	public long funcptr;

	public NativeActionListener(long funcptr) {
		this.funcptr = funcptr;
	}

	public void actionPerformed(java.awt.event.ActionEvent e) {
		NativeCallback.run(funcptr, e);
	}
}
