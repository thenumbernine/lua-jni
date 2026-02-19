-- this is the loader for the io.github.thenumbernine.NativeRunnable class

-- build the jni
require 'java.build'.C{
	src='runnable_lib.c',
	dst='librunnable_lib.so',
}

-- build the java
require 'java.build'.java{
	src='io/github/thenumbernine/NativeRunnable.java',
	dst='io/github/thenumbernine/NativeRunnable.class',
}
