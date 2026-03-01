/*
This is the only entry point required to do the rest of the LuaJIT -> Java -> LuaJIT stuff.
Maybe somehow I'll modify the symbol table live and then write this at runtime from a LuaJIT closure myself.
Until then, compile with:
> gcc -shared -fPIC -I"$JAVA_HOME/include" -I"$JAVA_HOME/include/linux" -o libio_github_thenumbernine_NativeCallback.so io_github_thenumbernine_NativeCallback.c
*/
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
//printf("native callback result %p\n", results);
	return results;
}
