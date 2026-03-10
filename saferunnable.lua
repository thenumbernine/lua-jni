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
local jni = require 'java.ffi.jni'
local ffi = require 'ffi'
local assert = require 'ext.assert'
local class = require 'ext.class'
local JavaObject = require 'java.object'
local LiteThread = require 'thread.lite'

local M = {}

-- [[
-- TODO TODO TODO
-- __gc in either is causing segfaults upon JavaVM's construction...
-- so subclass them locally and here override their __gc function
LiteThread = LiteThread:subclass()
function LiteThread:__gc() end
LiteThread.Lua = LiteThread.Lua:subclass()
function LiteThread.Lua:__gc() end
--]]

-- make the threadFuncTypeName match those for JNI java.lang.Runnable's run() native signature
LiteThread.threadFuncTypeName = jni.JNIEXPORT..' void '..jni.JNICALL..' (*)(JNIEnv*, jobject)'

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

	local thread = LiteThread{
		-- callback prefix code.
		-- I need to require java.ffi.jni in here,
		--  or the ffi.cast(threadFuncTypeName) won't work
		init = function(thread)
			-- this is needed for the ffi.cast threadFuncTypeName declaration
			thread.lua[[require 'java.ffi.jni']]

			--[=[ this is only necessary if we are rebuilding the JavaVM first, below:
			thread.lua([[jvmPtr = ... ]], ffi.cast('uint64_t', env._vm._ptr))
			--]=]

			-- convert to bytecode and pass into the child Lua state:
			thread.lua([[debug.getregistry().java_lang_Runnable_run_callback = ... ]], func)
		end,
		-- callback function:
		func = function(envPtr, this)
			-- THIS IS RUN ON A SEPARATE THREAD AND IN THE CHILD LUA STATE

			-- [[ from JNIEnv
			local env = require 'java.jnienv'{ptr=envPtr}
			--]]
			--[[ from shared JavaVM pointer:
			-- This changes from the vm's GetEnv call, which wouldn't happen if it was run on the same thread...
			local env = require 'java.vm'{ptr=jvmPtr}.jniEnv
			--]]
			--[[ now since this is a callback fro a jni native call, we have to convert the args,
			-- which, for Runnable.run(), is just 'this'
			this = env:_javaToLuaArg(this, 'java.lang.Runnable')
			--]]
			-- [[ or if we want to query the class manually (to get the Runnable runtime-generated subclass name)
			local this = env:_fromJObject(this)
			--]]
			debug.getregistry().java_lang_Runnable_run_callback(env, this)
		end,
	}

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
