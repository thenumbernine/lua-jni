public class TestGLSurfaceViewRenderer implements android.opengl.GLSurfaceView.Renderer {
	public native void onSurfaceCreated(
		javax.microedition.khronos.opengles.GL10 gl,
		javax.microedition.khronos.egl.EGLConfig cfg
	);

	public native void onSurfaceChanged(
		javax.microedition.khronos.opengles.GL10 gl,
		int width,
		int height
	);

	public native void onDrawFrame(
		javax.microedition.khronos.opengles.GL10 gl
	);
}
