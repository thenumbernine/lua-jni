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

-- TODO how to build a JavaFX app without subclassing anything ...
-- it is possible with Swing up to the exception of making your own Runnable (hence NativeRunnable)
-- ... probably not.
-- you'd probably need a Application subclass , then do ...
-- TODO try with ASM dynamically generated classes

-- this will just error
J.javafx.application.Application:launch(nil)
