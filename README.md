# JNI in LuaJIT

Alright, so I've got my [SDL-LuaJIT](https://github.com/thenumbernine/SDLLuaJIT-android) launcher.

It launches into LuaJIT just fine.

From there, LuaJIT can access any C function just fine.

I have a simple function set up to save and relay the `JNIEnv`.

Next, using this library, I will use LuaJIT to access JNI to do JNI stuff.

This is just [`lua-include`](https://github.com/thenumbernine/include-lua) run on `jni.h`.
