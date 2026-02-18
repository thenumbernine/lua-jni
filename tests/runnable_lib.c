// gcc -I"$JAVA_HOME/include" -I"$JAVA_HOME/include/linux" -shared -fPIC -o librunnable_lib.so runnable_lib.c
#include <jni.h>
#include <stdio.h>

JNIEXPORT void JNICALL Java_Runnable_runNative(JNIEnv * env, jclass class_) {
	printf("testing testing\n");
}
