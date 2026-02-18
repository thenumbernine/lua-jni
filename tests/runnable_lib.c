// gcc -I"$JAVA_HOME/include" -I"$JAVA_HOME/include/linux" -shared -fPIC -o librunnable_lib.so runnable_lib.c
#include <jni.h>
#include <stdio.h>

JNIEXPORT jlong JNICALL Java_TestNativeRunnable_runNative(JNIEnv * env, jobject this_, jlong jfuncptr, jlong jarg) {
	void* vfptr = (void*)jfuncptr;
	void* arg = (void*)jarg;
	jlong results = 0;
	if (!vfptr) {
		fprintf(stderr, "!!! DANGER !!! TestNativeRunnable called with null function pointer !!!\n");
	} else {
		void *(*fptr)(void*) = (void*(*)(void*))vfptr;
		results = (jlong)fptr(arg);
	}
	return results;
}
