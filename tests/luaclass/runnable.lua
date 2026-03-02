#!/usr/bin/env luajit
local J = require 'java'
J.Runnable(function(this)
	print('hello from within Lua', this)
end):run()
