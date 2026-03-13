#!/usr/bin/env luajit

local J = require 'java'
-- _cb() will auto-cast from func ptr
-- notice that because we're passing a function-pointer and not a function, we can't use JavaClass's implicit-call / _new()
local runnable = J.Runnable:_cb(function(J, this)
	-- THIS IS RUN ON A SEPARATE THREAD AND IN THE CHILD LUA STATE
	print('hello from child thread Lua, this', this)

	print('J', J)
	print('J.System.out', J.System.out)
	J.System.out:println("LuaJIT -> Java -> JNI -> (new thread) -> LuaJIT -> Java -> printing here")

	J:_checkExceptions()
end, true)	-- true means make it thread-safe with a sub Lua state
local th = J.Thread(runnable)

print('thread', th)

th:start()
th:join()
runnable:_getClass():_showLuaThreadErrors()
print'DONE'
