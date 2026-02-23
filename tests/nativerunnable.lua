-- this is the loader for the io.github.thenumbernine.NativeRunnable class

-- build the jni
require 'java.build'.C{
	src = 'io_github_thenumbernine_NativeRunnable.c',
	dst = 'libio_github_thenumbernine_NativeRunnable.so',
}

-- build the java
require 'java.build'.java{
	src = 'io/github/thenumbernine/NativeRunnable.java',
	dst = 'io/github/thenumbernine/NativeRunnable.class',
}
