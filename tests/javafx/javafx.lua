#!/usr/bin/env luajit
--[[
javafx demo but with java.luaclass
--]]
local LuaClass = require 'java.luaclass'
local jvm = require 'java.vm'{
	options = {
		['--module-path'] = '/usr/share/openjfx/lib',
		['--add-modules'] = 'javafx.controls,javafx.fxml',
	},
}
local J = jvm.jniEnv

-- the java-asm one loads a static field funcptr and calls it with NativeCallback
-- this is going to use closures.
local ThisApplication = LuaClass{
	env = J,
	isPublic = true,
	extends = 'javafx.application.Application',
	methods = {
		-- public void start(javafx.stage.Stage stage) { NativeCallback.run(funcptr, stage); }
		{
			name = 'start',
			sig = {'void', 'javafx.stage.Stage'},
			newLuaState = true,
			value = function(J, this, stage)
				-- THIS IS CALLED FROM A NEW THREAD

				stage:setTitle'Hello World!'

				local btn = J.javafx.scene.control.Button()
				btn:setText'Click Me!'
				btn:setOnAction(J.javafx.event.EventHandler(function(handler, event)
					print('got click', handler, event)
				end))

				local root = J.javafx.scene.layout.StackPane()
				root:getChildren():add(btn)
				stage:setScene(J.javafx.scene.Scene(root, 300, 250))

				stage:show()
			end,
		},
	},
}

--ThisApplication:launch()	-- "JVM java.lang.RuntimeException: Error: unable to determine Application class"
ThisApplication:launch(ThisApplication.class)
ThisApplication:_showLuaThreadErrors()
