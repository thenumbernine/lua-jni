#!/usr/bin/env luajit
local J = require 'java'
J.Runnable(function(...)
	print('hello from within Lua', ...)
end):run()
