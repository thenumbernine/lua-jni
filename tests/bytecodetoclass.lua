--[[
This is used by a few of the tests.

How to load a class from bytecode?

It'd be nice to have a method that worked without file-writes, without extra javac's

The first one does, but it also requires you be calling it from within Java, so it won't work from a JNI C app.

TODO should this accept slash-sep or dot-sep classes?
--]]
local M = {}

--return function(J, code, newClassName)

M.JNIDefineClass = function(J, code, newClassName)
	newClassName = newClassName:gsub('%.', '/')
	local loader = J.Thread:currentThread():getContextClassLoader()
	J:_checkExceptions()
	local jclass = J._ptr[0].DefineClass(J._ptr, newClassName, loader._ptr, code, #code)
	J:_checkExceptions()	-- is DefineClass supposed to throw an exception on failure?
	-- cuz on Android it's not...
	if jclass == nil then
		error("JNI DefineClass failed to load "..tostring(newClassName))
	end
	return J:_getClassForJClass(jclass)
end

M.MethodHandlesLookup = function(J, code)	-- Notice this fails from JNI from C, but I bet it'd work in Android Java app.
	local MethodHandles = J.java.lang.invoke.MethodHandles
	local lookup = MethodHandles:lookup()	-- "JVM java.lang.IllegalCallerException: no caller frame"
	return lookup:defineClass(code)		-- in Android this gives "attempt to call method 'defineClass' (a nil value)"
end

	--[[ upon "defineClass", throws "JVM java.lang.IllegalAccessException: Lookup does not have PACKAGE access"
	local MethodHandles = J.java.lang.invoke.MethodHandles
	local lookup = MethodHandles:publicLookup()
	return lookup:defineClass(code)
	--]]
	--[[
	local MethodHandles = J.java.lang.invoke.MethodHandles
	local publicLookup = MethodHandles:publicLookup()
	--local lookup = publicLookup['in'](publicLookup, ClassWriter.class)	-- upon :defineClass(), "JVM java.lang.IllegalAccessException: Lookup does not have PACKAGE access"
	local lookup = publicLookup['in'](publicLookup, J.Object.class)	--  upon :defineClass(), "JVM java.lang.IllegalAccessException: Lookup does not have PACKAGE access"
	return lookup:defineClass(code)
	--]]
	--[[
	local MethodHandles = J.java.lang.invoke.MethodHandles
	local publicLookup = MethodHandles:publicLookup()
	local lookup = MethodHandles:privateLookupIn(ClassWriter.class, publicLookup)	-- "JVM java.lang.IllegalAccessException: caller does not have PRIVATE and MODULE lookup mode"
	return lookup:defineClass(code)
	--]]
	--[[
	local MethodHandles = J.java.lang.invoke.MethodHandles
	local publicLookup = MethodHandles:publicLookup()
	return publicLookup:defineHiddenClass(code, true)	-- "JVM java.lang.IllegalAccessException: java.lang.Object/publicLookup does not have full privilege access"
	--return publicLookup:defineHiddenClass(code, false)	-- "JVM java.lang.IllegalAccessException: java.lang.Object/publicLookup does not have full privilege access"
	--]]
	
-- this works but it relies, once again, on an external class.
-- but unlike the URIClassLoader, this is just one written class, not many.
M.LookupFactory = function(J, code)
	require 'java.build'.java{
		src = 'io/github/thenumbernine/LookupFactory.java',
		dst = 'io/github/thenumbernine/LookupFactory.class',
	}
	local LookupFactory = J.io.github.thenumbernine.LookupFactory
	assert(require 'java.class':isa(LookupFactory))
	local lookup = LookupFactory:getFullAccess()
	return lookup:defineClass(code)
end
	
-- https://stackoverflow.com/questions/31226170/load-asm-generated-class-while-runtime
M.ClassLoader = function(J, code)
	-- still needs a custom subclass to be compiled ...
	-- ex: 
	--public class RuntimeClassLoader extends ClassLoader {
	--	public Class<?> defineClass(String name, byte[] b) {
	--		return defineClass(name, b, 0, b.length);
	--	}
	--}
	print(J.Class:getClassLoader())
	print(J.Class.class:getClassLoader())
	print(J.Class:getClass():getClassLoader())
	print(J.Thread:currentThread())
	local loader = J.Thread:currentThread():getContextClassLoader()
	print('loader', loader)
	return loader:defineClass(newClassName, code, 0, #code)
end
	
-- URLClassLoader, but that requires file write.  https://stackoverflow.com/a/1874179/2714073
-- path expects to be /-separated
M.URIClassLoader = function(J, code, newClassName)
assert(not newClassName:find'%.', "class should be /-separated")
	local ffi = require 'ffi'
	local path = require 'ext.path'
	do
		local fp = path(newClassName..'.class')
--DEBUG:print('writing to', fp)
		fp:getdir():mkdir(true)
		assert(fp:write(code))
	end
	local urls = J:_newArray(J.java.net.URL, 1, J.java.net.URL(J:_str('file://'..path:cwd())))
	local loader = J.java.net.URLClassLoader(urls)
	return loader:loadClass((newClassName:gsub('/', '.')))
end

-- pick a default
setmetatable(M, {
	__call = function(self, ...)
		-- [[ maybe this is the JNI preferred way?
		return self.JNIDefineClass(...)
		--]]
		--[[ doesn't work with CLI... maybe it will with Android?
		return self.MethodHandlesLookup(...)
		--]]
		--[[ works for runnable.lua and runnable_mt.lua
		-- but fails on the applet test
		-- because lua isn't sharing its cached java class between thread lua states
		return self.LookupFactory(...)
		--]]
		--[[ classloader?
		return self.ClassLoader(...)
		--]]
		--[[ works on applet
		return self.URIClassLoader(...)
		--]]
	end,
})

return M
