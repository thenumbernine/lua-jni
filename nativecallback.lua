--[[
Here's the fake-class used for the solve purpose of its one native function that a lot of other functions are using for Java calling into LuaJIT.
I guess with JavaClassData and JavaLuaClass, the need for this is getting slimmer and slimmer...
--]]
local ffi = require 'ffi'
local JavaClassData = require 'java.classdata'

local M = {}

--[[
JNIEXPORT jobject JNICALL
Java_io_github_thenumbernine_NativeCallback_run(
	JNIEnv * env,
	jclass this_,
	jlong jfuncptr,
	jobject jarg
) {
	void* vfptr = (void*)jfuncptr;
	void* results = NULL;
	if (!vfptr) {
		fprintf(stderr, "!!! DANGER !!! NativeCallback called with null function pointer !!!\n");
	} else {
		void *(*fptr)(void*) = (void*(*)(void*))vfptr;
		results = fptr(jarg);
	}
	return results;
}
--]]
M.nativeCallbackRunFunc = function(env, this, jfuncptr, jarg)
	local vfptr = ffi.cast('void*', jfuncptr)
	local results
	if vfptr == nil then
		io.stderr:write("!!! DANGER !!! NativeCallback called with null function pointer !!!\n")
	else
		-- in LuaJIT if I cast cdata to a function-pointer, does it create another closure object that I have to manually free?  I think no ...
		local fptr = ffi.cast('void*(*)(void*)', vfptr)
		results = fptr(jarg)
	end
	return results
end
M.nativeCallbackRunClosure = ffi.cast('jobject(*)(JNIEnv * env, jclass this_, jlong jfuncptr, jobject jarg)', M.nativeCallbackRunFunc)

M.runMethodName = 'run'
M.runMethodSig = '(JLjava/lang/Object;)Ljava/lang/Object;'

-- if Lua gc's this will Java complain?  Does Java copy it over upon function call?  I don't trust JNI's programmers....
M.nativeMethods = ffi.new'JNINativeMethod[1]'
M.nativeMethods[0].name = M.runMethodName
M.nativeMethods[0].signature = M.runMethodSig
M.nativeMethods[0].fnPtr = M.nativeCallbackRunClosure

function M:run(env)
	local newClassName = 'io.github.thenumbernine.NativeCallback'
	local newClassNameSlashSep = newClassName:gsub('%.', '/')

	-- check if it's already loaded
	local cl = env:_findClass(newClassName)
	if cl then
		rawset(cl, '_runMethodName', M.runMethodName)
		return cl
	end

	local classData = JavaClassData{
		version = 0x41,
		isPublic = true,
		isSuper = true,
		thisClass = newClassNameSlashSep,
		superClass = 'java/lang/Object',
		methods = {
			{	-- needs a ctor? even though it's never used?
				isPublic = true,
				name = '<init>',
				sig = '()V',
				code = [[
aload_0
invokespecial java/lang/Object <init> ()V
return
]],
				maxLocals = 1,
				maxStack = 1,
			},
			{
				isNative = true,
				isPublic = true,
				isStatic = true,
				name = M.runMethodName,
				sig = M.runMethodSig,
			},
		},
	}

	local cl = env:_defineClass(classData)

	-- now it looks like JNIEnv->RegisterNatives can allow you to manually set native methods instead of depending on symbol table.
	-- but I'm also reading that JNIEnv->RegisterNatives itself needs to be called from ... a specifically-named function in the symbol table ... smh.
	-- let's see if I can call it manually here ...
	env._ptr[0].RegisterNatives(env._ptr, cl._ptr, M.nativeMethods, 1)

	rawset(cl, '_runMethodName', M.runMethodName)
	return cl
end

return setmetatable(M, {
	__call = M.run,
})
