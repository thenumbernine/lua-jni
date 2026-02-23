// gcc -I"$JAVA_HOME/include" -I"$JAVA_HOME/include/linux" -shared -fPIC -o libio_github_thenumbernine_NativeRunnable.so io_github_thenumbernine_NativeRunnable.c
#include <jni.h>
#include <stdio.h>

JNIEXPORT jlong JNICALL Java_io_github_thenumbernine_NativeRunnable_runNative(JNIEnv * env, jclass this_, jlong jfuncptr, jlong jarg) {
	void* vfptr = (void*)jfuncptr;
	void* arg = (void*)jarg;
	jlong results = 0;
	if (!vfptr) {
		fprintf(stderr, "!!! DANGER !!! NativeRunnable called with null function pointer !!!\n");
	} else {
		void *(*fptr)(void*) = (void*(*)(void*))vfptr;
		results = (jlong)fptr(arg);
	}
	return results;
}
