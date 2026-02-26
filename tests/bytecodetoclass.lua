--[[
How to load a class from bytecode?

It'd be nice to have a method that worked without file-writes, without extra javac's

The first one does, but it also requires you be calling it from within Java, so it won't work from a JNI C app.
--]]
local M = {}

--return function(J, code, newClassName)
	--[[ Notice this fails from JNI from C, but I bet it'd work in Android Java app.
	local MethodHandles = J.java.lang.invoke.MethodHandles
	local lookup = MethodHandles:lookup()	-- "JVM java.lang.IllegalCallerException: no caller frame"
	return lookup:defineClass(code)
	--]]
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
	--[[ this works but it relies, once again, on an external class. smh i hate java.
	require 'java.build'.java{
		src = 'TestLookupFactory.java',
		dst = 'TestLookupFactory.class',
	}
	assert(require 'java.class':isa(J.TestLookupFactory))
	local lookup = J.TestLookupFactory:getFullAccess()
	return lookup:defineClass(code)
	--]]
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
	
-- [[ URLClassLoader, but that requires file write.  https://stackoverflow.com/a/1874179/2714073
-- path expects to be /-separated
M.URIClassLoader = function(J, code, newClassName)
assert(not newClassName:find'%.', "class should be /-separated")
	local ffi = require 'ffi'
	local path = require 'ext.path'
	do	-- TODO put this in the java lua api?
		-- either a convert-to-C function or even a get-raw-access function (that needs to be manually released...)
		local codeptr = J._ptr[0].GetByteArrayElements(J._ptr, code._ptr, nil)
		local fp = path(newClassName..'.class')
print('writing to', fp)
		fp:getdir():mkdir(true)
		assert(fp:write(ffi.string(codeptr, #code)))
		J._ptr[0].ReleaseByteArrayElements(J._ptr, code._ptr, codeptr, 0)
	end
	local urls = J:_newArray(J.java.net.URL, 1, J.java.net.URL(J:_str('file://'..path:cwd())))
	local loader = J.java.net.URLClassLoader(urls)
	return loader:loadClass((newClassName:gsub('/', '.')))
end
--]]

return M
