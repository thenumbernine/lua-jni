#!/usr/bin/env luajit
local J = require 'java'
J.Runnable(function(...)	-- SAM ctor
	print('hello from within Lua', ...)
end):run()
