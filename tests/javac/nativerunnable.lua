-- this is the loader for the io.github.thenumbernine.NativeRunnable class
-- this expects to be run from the java/tests/javac/ folder
local assert = require 'ext.assert'
return function(J)
	-- build the jni
	require 'java.build'.C{
		src = 'io_github_thenumbernine_NativeCallback.c',
		dst = 'libio_github_thenumbernine_NativeCallback.so',
	}

	-- build the java
	require 'java.build'.java{
		src = 'io/github/thenumbernine/NativeCallback.java',
		dst = 'io/github/thenumbernine/NativeCallback.class',
	}

	-- build the java
	require 'java.build'.java{
		-- NativeRunnable.java should compile NativeCallback.java
		src = 'io/github/thenumbernine/NativeRunnable.java',
		dst = 'io/github/thenumbernine/NativeRunnable.class',
	}

	return (assert.is(
		J.io.github.thenumbernine.NativeRunnable,
		require 'java.class',
		'failed to load io.github.thenumbernine.NativeRunnable'
	))
end
