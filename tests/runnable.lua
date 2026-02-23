#!/usr/bin/env luajit
--[[
Java provides no way to handle C functions, apart from its own JNI stuff
This means there's no way to pass in a LuaJIT->C closure callback to Java without going through JNI

How would I have a Java Runnable call a LuaJIT function?

Mind you this is not worrying about multithreading just yet.  Simply Runnable.
--]]

-- build
require 'java.tests.nativerunnable'

-- weird
-- the jvm is getting the option -Djava.library.path=.
-- it's running
-- it's not finding
local JVM = require 'java.vm'
local jvm = JVM{
	props = {
		['java.class.path'] = '.',
		['java.library.path'] = '.',
	}
}
local J = jvm.jniEnv

-- this loads librunnable_lib.so
-- so this can be used as an entry point for Java->JNI->LuaJIT code
print('J.io.github.thenumbernine.NativeRunnable', J.io.github.thenumbernine.NativeRunnable)
print('J.io.github.thenumbernine.NativeRunnable.run', J.io.github.thenumbernine.NativeRunnable.run)
print('J.io.github.thenumbernine.NativeRunnable.runNative', J.io.github.thenumbernine.NativeRunnable.runNative)

-- I'd return something, but
callback = function(arg)
	print('hello from within Lua, arg', arg)
end
local ffi = require 'ffi'
closure = ffi.cast('void *(*)(void*)', callback)	-- using a pthread signature here and in runnable_lib.c
J.io.github.thenumbernine.NativeRunnable:_new(ffi.cast('jlong', closure)):run()


-- can I do the same thing but without a trampoline class?
-- maybe with java.lang.reflect.Proxy?
-- probably yes up until I try to cross the native C call bridge.

-- [[ wait maybe this won't work
-- TODO I would need generics to get this to work
-- generics means I'd no longer cache methods by classpath alone (or would I?, could I just provide JavaClass instances per generic instances?)
local Runnable = J.java.lang.Runnable
print('Runnable', Runnable)

-- Runnable the jclass doesn't have an isInterface method
--print('Runnable.isInterface', Runnable.isInterface)			-- nil
--print('Runnable.getClassLoader', Runnable.getClassLoader)
print('java.lang.Class.getClassLoader', J.java.lang.Class.getClassLoader)

print('Runnable:_name()', Runnable:_name())	-- "java.lang.Runnable" ... wait is this equivalent to Runnable.class.getName() ?

-- doesn't work because ... ? 
-- 'getName' is a nil value ?
--print('Runnable:getName()', Runnable:getName())	
-- sure enough,  there's no "getName" in Runnable
--print('Runnable._members.getName', Runnable._members.getName)

-- but Runnable jclass can be treated as a jobject and called by java.lang.Class's member methods ...
print('java.lang.Class.getName(Runnable)', J.java.lang.Class.getName(Runnable))	-- "java.lang.Runnable"

-- the "_class()" method just reassigns the same pointer as a JavaObject with its ._classname as java.lang.Class ... trying to emulate java's .class syntax-sugar
print('Runnable:_class():getName()', Runnable:_class():getName())	-- works, same, "java.lang.Runnable"

--print('Runnable:_class():_name()', Runnable:_class():_name())	-- doesn't work because JavaObject doesn't have :_name()
print('Runnable:_class():_getClass()', Runnable:_class():_getClass())	-- JavaClass of java.lang.Class
print('Runnable:_class():_getClass():_class()', Runnable:_class():_getClass():_class())	-- JavaObject of java.lang.Class
print('Runnable:_class():_getClass():getName()', Runnable:_class():_getClass():getName()) 	-- "java.lang.Class"
print('Runnable:_class():_getClass():_class():getName()', Runnable:_class():_getClass():_class():getName())	-- "java.lang.Class"
print('Runnable:_class():isInterface()', Runnable:_class():isInterface())
-- but it's not finding this ...
print('Runnable:_class():getClassLoader()', Runnable:_class():getClassLoader())	-- wait ... .class exists in Java, right?

--[=[ and last the handler , ... which has to be a subclass anyways ...
local Proxy = J.java.lang.reflect.Proxy
print('Proxy', Proxy)

local proxyRunnable = Proxy:newProxyInstance(
	Runnable:_class():getClassLoader(),
	J:_newArray(J.java.lang.Class, 1, Runnable:_class()),
	handler
)
print('proxyRunnable', proxyRunnable)
--]=]
--]]
