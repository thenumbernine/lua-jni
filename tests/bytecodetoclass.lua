--[[
How to load a class from bytecode?

It'd be nice to have a method that worked without file-writes, without extra javac's

The first one does, but it also requires you be calling it from within Java, so it won't work from a JNI C app.
--]]
local M = {}

--return function(J, code, newClassName)

M.JNIDefineClass = function(J, code, newClassName)
	local codeptr = code:_map()
	local jclass = J._ptr[0].DefineClass(J._ptr, newClassName, nil, codeptr, #code)
	code:_unmap(codeptr)
	return J:_getClassForJClass(jclass)
end

M.MethodHandlesLookup = function(J, code)	-- Notice this fails from JNI from C, but I bet it'd work in Android Java app.
	local MethodHandles = J.java.lang.invoke.MethodHandles
	local lookup = MethodHandles:lookup()	-- "JVM java.lang.IllegalCallerException: no caller frame"
	return lookup:defineClass(code)
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
	
	--[[ https://stackoverflow.com/questions/31226170/load-asm-generated-class-while-runtime
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
	--]]
	
-- URLClassLoader, but that requires file write.  https://stackoverflow.com/a/1874179/2714073
-- path expects to be /-separated
M.URIClassLoader = function(J, code, newClassName)
assert(not newClassName:find'%.', "class should be /-separated")
	local ffi = require 'ffi'
	local path = require 'ext.path'
	do	-- TODO put this in the java lua api?
		-- either a convert-to-C function or even a get-raw-access function (that needs to be manually released...)
		local codeptr = J._ptr[0].GetByteArrayElements(J._ptr, code._ptr, nil)
		local fp = path(newClassName..'.class')
--DEBUG:print('writing to', fp)
		fp:getdir():mkdir(true)
		assert(fp:write(ffi.string(codeptr, #code)))
		J._ptr[0].ReleaseByteArrayElements(J._ptr, code._ptr, codeptr, 0)
	end
	local urls = J:_newArray(J.java.net.URL, 1, J.java.net.URL(J:_str('file://'..path:cwd())))
	local loader = J.java.net.URLClassLoader(urls)
	return loader:loadClass((newClassName:gsub('/', '.')))
end

-- pick a default
setmetatable(M, {
	__call = function(self, ...)
		--[[ maybe this is the JNI preferred way?
		-- but when you use nil for classloader, then in new threads, it seems it cannot find classes inside jars ... hmm
		return self.JNIDefineClass(...)
		--]]
		--[[ doesn't work with CLI... maybe it will with Android?
		return self.MethodHandlesLookup(...)
		--]]
		-- [[ works for runnable.lua and runnable_mt.lua
		-- but fails on the applet test
		-- because lua isn't sharing its cached java class between thread lua states
		return self.LookupFactory(...)
		--]]
		--[[ works on applet
		return self.URIClassLoader(...)
		--]]
	end,
})

return M
