--[[
Implementation of the lua-thread project thread/lite.lua but for java/vm.lua usage

This is *not* a wrapper for java.lang.Thread (like the other Lua files are wrappers of Java classes).
... maybe it'll become one? not sure...

This is a wrapper for creating the C callback closures and Lua sub-state, and handing off the JVM and rebuilding the new Java thread's JNIEnv.

Any time in Lua-Java that you are going to pass a Runnable to something that's going to spawn a new thread, you must use this instead.

Maybe I should change the name to JavaThreadSafeRunnable ? hmm...

Maybe I should provide this function-as-ctor option to lite-thread ?
--]]
local ffi = require 'ffi'
local assert = require 'ext.assert'
local class = require 'ext.class'
local JavaObject = require 'java.object'
local LiteThread = require 'thread.lite'

-- TODO TODO TODO
-- this is causing segfaults upon JavaVM's construction...
require 'lua'.__gc = function() end
require 'thread.lite'.__gc = function() end


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

	local thread = LiteThread{
		code = [=[
	-- This changes from the vm's GetEnv call, which wouldn't happen if it was run on the same thread...
	local env = require 'java.vm'{ptr=jvmPtr}.jniEnv
	local jarg = env:_fromJObject(arg)
	local javaCallback = assert(load(javaCallbackBC))
	javaCallback(env, jarg:_unpack())
]=],
}
	thread.lua([[ jvmPtr = ... ]], ffi.cast('uint64_t', env._vm._ptr))
	thread.lua([[ javaCallbackBC = ... ]], string.dump(func))

	-- hmm gc problems ...
	-- my child lua state is gc'ing too quickly
	-- assigning here doesn't matter. ..
	-- can't assign it to the object, because the Lua object will gc long before the Java one does ...
	-- my fix is to disable thread.lite and lua gc from here for the time being...
	--self._thread = thread

	-- can't use ctor since ctor autodetects SAM-function-wrapping if a function is passed, and we're passing a cdata function-pointer
	local obj = env.Runnable:_cb(thread.funcptr)
	rawset(obj, '_thread', thread)
	-- do this but after done running
	--thread:showErr()

	return obj
end

return setmetatable(M, {
	__call = M.run,
})
