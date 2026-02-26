// gcc -I"$JAVA_HOME/include" -I"$JAVA_HOME/include/linux" -shared -fPIC -o libio_github_thenumbernine_NativeCallback.so io_github_thenumbernine_NativeCallback.c
#include <jni.h>
#include <stdio.h>

JNIEXPORT jobject JNICALL Java_io_github_thenumbernine_NativeCallback_run(JNIEnv * env, jclass this_, jlong jfuncptr, jobject jarg) {
//printf("native callback fptr %p arg %p\n", (void*)jfuncptr, jarg);
	void* vfptr = (void*)jfuncptr;
	void* results = NULL;
	if (!vfptr) {
		fprintf(stderr, "!!! DANGER !!! NativeCallback called with null function pointer !!!\n");
	} else {
		void *(*fptr)(void*) = (void*(*)(void*))vfptr;
		results = fptr(jarg);
	}
	return results;
}
