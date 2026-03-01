#!/usr/bin/env luajit
--[[
javafx demo but with java.luaclass
--]]
local thread = require 'thread.lite'{
	code = [=[
	print('Application:start(stage) callback')
	local J = require 'java.vm'{ptr=jvmPtr}.jniEnv
	print('J._ptr', J._ptr)	-- changes from the vm's GetEnv call, which wouldn't happen if it was run on the same thread...

	local pthread = require 'ffi.req' 'c.pthread'
	local callbackThread = pthread.pthread_self()
	print('callback thread, pthread_self', callbackThread)
	
	local stage = arg
	print('stage', stage)
	stage = J:_javaToLuaArg(stage, 'javafx.stage.Stage')
	print('stage', stage)

	stage:setTitle'Hello World!'

	local btn = J.javafx.scene.control.Button
	btn:setText'Button 1'

	local root = J.javafx.scene.layout.StackPane()
	root:getChildren():add(btn)
	stage:setScene(
		J.javafx.scene.Scene(root, 300, 250)
	)
	stage:show()
]=],
}

local jvm = require 'java.vm'{
	options = {
		['--module-path'] = '/usr/share/openjfx/lib',
		['--add-modules'] = 'javafx.controls,javafx.fxml',
	},
	props = {
		['java.class.path'] = table.concat({
			'asm-9.9.1.jar',		-- needed for ASM
			'.',
		}, ':'),
		--['java.library.path'] = '.',
	}
}
local J = jvm.jniEnv
print('JNIEnv', J._ptr)

local ffi = require 'ffi'
thread.lua([[ jvmPtr = ... ]], ffi.cast('uint64_t', J._vm._ptr))

-- show the main thread is one thread
local pthread = require 'ffi.req' 'c.pthread'
local parentThread = pthread.pthread_self()
print('parent thread, pthread_self', parentThread)

-- the java-asm one loads a static field funcptr and calls it with NativeCallback
-- this is going to use closures. 
local ThisApplication = require 'java.luaclass'{
	env = J,
	isPublic = true,
	name = 'io.github.thenumbernine.ThisApplication',
	extends = 'javafx.application.Application',
	methods = {
		-- public void start(javafx.stage.Stage stage) { NativeCallback.run(funcptr, stage); }
		{
			isPublic = true,
			name = 'start',
			sig = {'void', 'javafx.stage.Stage'},
			func = thread.funcptr,	-- thread will get called with 'stage'
		},
	},
}

--ThisApplication:launch()	-- "JVM java.lang.RuntimeException: Error: unable to determine Application class"
ThisApplication:launch(ThisApplication.class)
