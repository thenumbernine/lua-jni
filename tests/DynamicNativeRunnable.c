// gcc -I"$JAVA_HOME/include" -I"$JAVA_HOME/include/linux" -shared -fPIC -o libDynamicNativeRunnable.so DynamicNativeRunnable.c
#include <jni.h>
#include <stdio.h>

JNIEXPORT jlong JNICALL Java_DynamicNativeRunnable_runNative(JNIEnv * env, jclass this_, jlong jfuncptr, jlong jarg) {
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

