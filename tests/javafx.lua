#!/usr/bin/env luajit
--[[
so when going from javax.swing to javafx.*
... Java added the required constraint extra module cmdline cfg crap
... and Java added the required constraint of subclassing a class just to make an app
.. so it's double the headache,
and until I do something like bytecode injection to build classes at runtime...
... this demo won't get finished.

--]]

local J = require 'java.vm'{
	options = {
		['--module-path'] = '/usr/share/openjfx/lib',
		['--add-modules'] = 'javafx.controls,javafx.fxml',
	},
	props = {
		['java.class.path'] = '.',
		['java.library.path'] = '.',
	}
}.jniEnv

local NativeRunnable = require 'java.tests.nativerunnable'(J)	-- build

--[[
How to build a JavaFX app without subclassing anything ...
it is possible with Swing up to the exception of making your own Runnable (hence NativeRunnable)
... probably not.
you'd probably need a Application subclass , then do ...

I could do this with ASM ...
I currently need a layer on it for converting Java<->Lua
especially for passing in ActionListener events to Lua
and javafx.Application javafx.stage.Stage's
maybe I could use the java.jnienv Lua class's translation for that ...
Then how to get the vararg Java objects to jobjects before calling into C? (since I don't want to make multiple stub codes ...
One fix is to replace the JNI arg with a jobject that points to an Object[] that the LuaJIT side has to decode...
Then the Java code would call io.github.thenumbernine.NativeCallback.run(long closureAddr, Object[]{args...})
(but this but in Java-ASM calls...)
--]]

-- this will just error
J.javafx.application.Application:launch(nil)
