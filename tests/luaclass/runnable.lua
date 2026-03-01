#!/usr/bin/env luajit
local J = require 'java'
function callback(this)
	print('hello from within Lua', this)
end
J.Runnable:_cb(callback):run()
