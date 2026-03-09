--[[
Implementation of the lua-thread project thread/lite.lua but for java/vm.lua usage

Also packs and unpacks Java arguments similar to what JavaLuaClass calls would do.

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
local Lua = require 'lua'

local LiteThread = require 'thread.lite'

-- [[
-- TODO TODO TODO
-- __gc in either is causing segfaults upon JavaVM's construction...
-- so subclass them locally and here override their __gc function
LiteThread = LiteThread:subclass()
function LiteThread:__gc() end
LiteThread.Lua = LiteThread.Lua:subclass()
function LiteThread.Lua:__gc() end
--]]

local M = {}

--[[
-- how to track java object garbage collection
-- https://stackoverflow.com/questions/74373440/how-to-garbage-collect-callbacks-with-weak-references-in-java
function M:trackJavaObject(env, obj)
	if not M.queue then
		M.queue = env.java.lang.ref.ReferenceQueue()
		local weakRef = env.java.lang.ref.WeakReference(obj, queue)

		-- start a monitoring thread here ...
		-- ... can I do it on same thread? probably not?
		-- hmm chicken and the egg, I want to use this for thread cleanup ...
		-- maybe that means I have to run one and only one of these to handle all my java cleanup?
		--
	end
end
--]]

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

	local thread = LiteThread(function(arg)
		-- THIS IS RUN IN THE CHILD LUA STATE
		-- This changes from the vm's GetEnv call, which wouldn't happen if it was run on the same thread...
		local env = require 'java.vm'{ptr=jvmPtr}.jniEnv
		local jarg = env:_fromJObject(arg)
		javaCallback(env, jarg:_unpack())
	end)
	thread.lua([[jvmPtr = ... ]], ffi.cast('uint64_t', env._vm._ptr))
	thread.lua([[javaCallback = ... ]], func)

	-- hmm gc problems ...
	-- my child lua state is gc'ing too quickly
	-- assigning here doesn't matter. ..
	-- can't assign it to the object, because the Lua object will gc long before the Java one does ...
	-- my fix is to disable thread.lite and lua gc from here for the time being...
	--self._thread = thread

	-- Can't use Runnable() since ctor autodetects SAM-function-wrapping if a function is passed,
	--  and we're passing a cdata function-pointer.
	local obj = env.Runnable:_cb(thread.funcptr)
	rawset(obj, '_thread', thread)

	-- do this but after done running
	--thread:showErr()

	-- it would be nice to have a java-on-gc callback so that I could associate this Lua object with the jobject
	--  and then only clean up the associated resources (callback, sub-lua-state, etc) upon java object's collect...
	-- let's try ...
	--M:trackJavaObject(env, obj)

	return obj
end

return setmetatable(M, {
	__call = M.run,
})
