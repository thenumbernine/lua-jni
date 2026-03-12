--[[
This is getting pushed back into luaclass
--]]
local jni = require 'java.ffi.jni'
local assert = require 'ext.assert'

local M = {}

--[[
args:
	env = java/jnienv.lua instance
	func = function to call.
		NOTICE the calling function CANNOT talk to the outside world, or that'll cross the streams...
		func is called with `func(env, this)`
--]]
function M:run(args)
	local env = assert.index(args, 'env')
	local func = assert.type(assert.index(args, 'func'), 'function')

	-- _cb(func, true) true means new-lua-state / new-thread-safe
	local RunnableSubclass = env.Runnable:_cbClass(func, true)
	return RunnableSubclass()
end

return setmetatable(M, {
	__call = M.run,
})
