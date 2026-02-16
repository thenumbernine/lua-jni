-- if this is the central point then 
-- this should return a function for wrapping a C JNIEnv* into the java.env class ...
return function(jniEnv)
	return require 'java.jnienv'(jniEnv)
end
