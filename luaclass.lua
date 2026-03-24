--[[
auto-gen java bytecode at runtime to make a glue-class whose methods point to Lua functions
uses java/nativecallback.lua to do its LuaJIT->Java->LuaJIT, but honestly we're getting to the point where I can just inline that myself...
--]]
local jni = require 'java.ffi.jni'		-- get cdefs
local ffi = require 'ffi'
local assert = require 'ext.assert'
local table = require 'ext.table'
local vector = require 'stl.vector-lua'
local JNIEnv = require 'java.jnienv'

local java_util = require 'java.util'
local getJNISig = java_util .getJNISig
local infoForPrims = java_util.infoForPrims


local LiteThread = require 'thread.lite'
-- TODO , __gc on litethreads and luastates is causing javavm segfaults
-- they are collecting too quickly and i can't seem to pin them correctly to keep them from collecting
-- so here is me just disabling their __gc
LiteThread = LiteThread:subclass()
function LiteThread:__gc() end
LiteThread.Lua = LiteThread.Lua:subclass()
function LiteThread.Lua:__gc() end


local function jniTypeForSig(s)
	if s == 'void 'then return 'void' end
	if s == 'java.lang.String' then return 'jstring' end
	local primInfo = infoForPrims[s]
	if primInfo then return 'j'..s end
	return 'jobject'
end

local function getCFuncTypeForSig(sig, isStatic)
	-- build wrapper for args here:
	local jniCSig = table()
	jniCSig:insert(jni.JNIEXPORT..' ')
	jniCSig:insert(jniTypeForSig(sig[1]))
	jniCSig:insert(' '..jni.JNICALL)
	jniCSig:insert'(*)(JNIEnv*'	-- function args begin
	if isStatic then
		jniCSig:insert', jclass'	-- calling class
	else
		jniCSig:insert', jobject'	-- this
	end
	for i=2,#sig do
		jniCSig:insert(', '..jniTypeForSig(sig[i]))
	end
	jniCSig:insert')'		-- function args end
--DEBUG:print('for method', isStatic and 'static' or '', 'sig', require 'ext.tolua'(sig))
	return jniCSig:concat()
end


local uniqueNameCounter = 1

local function generateName(base, ptr)
	local name = base
		..'_'..bit.tohex(ffi.cast('uint64_t', ptr), bit.lshift(ffi.sizeof'intptr_t', 1))
		..'_'..uniqueNameCounter
	uniqueNameCounter = uniqueNameCounter + 1
	return name
end


-- Where to put the saved closures?
-- I'd put them in the JavaClass object but I'm sure it would go out of scope too quickly
-- So I'll put them here with key = classpath
local M = {}
M.savedClosures = {}
M.classnameBase = 'io.github.thenumbernine.LuaJavaClass_'

--[[
args:
	env = JavaEnv
	name = (optional) dot-separated class name
	extends = (optional) parent-class, or java.lang.Object by default
	implements = (optional) list-of-interfaces to use
	fields = (optional) {
		{
			name =
			sig = string of dot-separated java type (primitive, class, array, etc)
			value = JavaASMClass constant descriptor table of initial value
			isStatic =
			isPublic =
			isPrivate =
			...
		},
		...
	}
	ctors = (optional) {
		{
			value = Lua callback function
			sig = table, 1st is return value, rest are dot-separated typename arguments,
			isPrivate =
			isPublic =
		},
		...
	}
	methods = (optional) {
		{
			name =
			sig = table, 1st is return value, rest are dot-separated typename arguments,
			value = Lua callback function, or cdata pointer to C function
			isVarArgs
			isStatic
			isPublic
			isPrivate
			...

			newLuaState = set to 'true' to have the native callback run in a new sub-Lua-state.
				This is necessary for functions that will run in separate threads from their callers, i.e. Runnable.run(), javafx's Application.start(), etc.
		}
	}

	TODO:
	isPublic
	isPrivate
	isProtected
	isAbstract
	isInterface		<- btw what is an interface class's parent class?

	usingAndroidJNI = set to non-nil to override the env's _usingAndroidJNI
	returnASMArgsOnly = set to 'true' to just return the class args, don't load it
	returnASMOnly = set to 'true' to just return the class, don't load it
--]]
function M:run(args)
	local env = assert.index(args, 'env')

	local isAndroid = args.usingAndroidJNI
	if isAndroid == nil then isAndroid = env._usingAndroidJNI end

	local classpath = args.name
	if not classpath then
		classpath = generateName(M.classnameBase, env._ptr)
	end

	local parentClass = args.extends or 'java.lang.Object'

	local interfaces
	if args.implements then
		interfaces = table()
		for i,name in ipairs(args.implements) do
			if type(name) == 'string' then
			elseif type(name) == 'table' then
				if not require 'java.class':isa(name) then
					error(".interfaces["..i.."] expects a string or a JavaClass")
				end
				name = name._classpath
			else
				error(".interfaces["..i.."] expects a string or a JavaClass")
			end
			interfaces[i] = name
		end
	end

	local closures = table()	-- to-free
	M.savedClosures[classpath] =  closures


	local asmClassArgs = {
		version = 0x41,
		isPublic = true,
		thisClass = classpath,
		superClass = parentClass,
		interfaces = interfaces,
		fields = table(),
		methods = table(),
	}
	if not isAndroid then
		asmClassArgs.isSuper = true	-- .class only
	end

	local nativeMethods = vector'JNINativeMethod'

	-- for JavaClass in case we are using newLuaState
	local usingNewLuaState

	-- pairs() order is non-deterministic
	-- but I think pairs() does ipairs integer indexes in order at least?
	if args.fields then
		for key,field in pairs(args.fields) do
			if type(key) == 'string' then

				-- an extra inception layer here could be inferring value from field type,
				-- but then string would be ambiguous (maybe I'd get rid of that?)

				if type(field) == 'string' then
					-- string = string <=> name = sig
					field = {
						name = key,
						sig = field,
						isPublic = true,
					}
				else
					-- string = table <=> name = properties
					assert.type(field, 'table')
					if not field.name then
						field.name = key
					end
				end
			elseif type(field) == 'string' then
				-- if the key is sequentially indexed,
				-- and value is string
				-- ... then value will be the name, and type will be implicit
				field = {
					name = field,
					sig = 'java.lang.Object',
					isPublic = true,
				}
			end
			assert.type(field, 'table')

			--[[ default.  i know i should let this fall back on package-scope i.e. no public/private/protected.  meh.
			if field.isPublic == nil
			and field.isPrivate == nil
			and field.isProtected == nil
			then
				field.isPublic = true
			end
			--]]

			field.name = assert.type(assert.index(field, 'name'), 'string')

			assert.type(assert.index(field, 'sig'), 'string')

			-- TODO here some conversion of constant value based on type or something
			if field.value then
			end

			asmClassArgs.fields:insert(field)
		end
	end

	local function fixMethodSig(method)
		local sig = method.sig

		if not sig then
			if method.name == 'toString' then
				sig = {'java.lang.String'}	-- default toString to String()
			else
				sig = {}	-- default to void()
			end
			method.sig = sig
		end
		sig[1] = sig[1] or 'void'

		-- I need to hold onto this for at least the duration of nativeMethods[]
		method.jniSig = getJNISig(sig)

		-- fun fact, defining toString() with a return type other than the java.lang.String makes the VM segfault
		-- adding extra args to toString() makes the VM give you a warning
		if method.name == 'toString'
		and method.jniSig ~= '()Ljava/lang/String;'
		then
			io.stderr:write'!!! WARNING !!! You are defining a class method toString() with an atypical signature.  In my experience the VM will segfault next, or just warn you if you are lucky.  Enjoy.\n'
		end
	end

	local srcCtors = args.ctors
	if not srcCtors or #srcCtors == 0 then
		-- provide a default ctor, no need for closure or callback
		if isAndroid then
			asmClassArgs.methods:insert{
				isPublic = true,
				isConstructor = true,
				name = '<init>',
				sig = {'void'},
				maxRegs = 1,
				regsIn = 1,
				regsOut = 1,
				code = [[
invoke-direct ]]..getJNISig(parentClass)..[[ <init> ()V v0
return-void
]],
			}
		else
			asmClassArgs.methods:insert{
				isPublic = true,
				name = '<init>',
				sig = {'void'},
				maxStack = 1,
				maxLocals = 1,
				code = [[
aload_0
invokespecial ]]..parentClass..[[ <init> ()V
return
]],
			}
		end
	else
		args.methods = table(args.methods)	-- will be using this
		for _,ctor in ipairs(args.ctors) do
			if type(ctor) == 'function' then
				ctor = {
					value = ctor,
					isPublic = true,
				}
			end

			assert.type(ctor.value, 'function')

			ctor.name = '<init>'
			ctor.sig = ctor.sig or {'void'}
			ctor.sig[1] = 'void'		-- ctor must return void
			ctor.isStatic = false		-- ctor must not be static
			ctor.isConstructor = true	-- .dex only

			fixMethodSig(ctor)
			local sig = ctor.sig
			local returnType = sig[1]

			local ctorFwdMethodName = generateName('ctorFwdMethod', env._ptr)
			args.methods:insert{
				name = ctorFwdMethodName,
				isPrivate = true,
				sig = table(sig),
				value = ctor.value,	-- passed value goes here.
			}


			-- map from arg # (1-based) to stack or register index # (0-based)
			local argIndex = table()
			local maxArgIndex = 1

			local sigNumArgs = #sig-1
			local argArraySize = sigNumArgs+1	-- +1 for 'this' unless it's static

			for i=1,sigNumArgs do
				argIndex[i] = maxArgIndex
				local primInfo = infoForPrims[sig[i+1]]
				maxArgIndex = maxArgIndex + (primInfo and primInfo.argSize or 1)
			end

			if isAndroid then
				ctor.regsOut = maxArgIndex
				ctor.regsIn = maxArgIndex
				ctor.maxRegs = maxArgIndex
			end

			local code = table()

			-- .class-only, since .dex doesn't use a stack
			local function pushConstInt(value)
				if value == -1 then
					code:insert{'iconst_m1'}
				elseif value >= 0 and value <= 5 then
					code:insert{'iconst_'..value}
				else
					const:insert{'bipush', value}
				end
			end

			-- special for ctors, call parent
			if isAndroid then
				code:insert{'invoke-direct', getJNISig(parentClass), '<init>', '()V', 'v0'}	-- v0 has 'this'

				local regs = table()
				for i=1,sigNumArgs do
					regs:insert('v'..argIndex[i])
					local primInfo = infoForPrims[sig[i+1]]
					if primInfo and primInfo.argSize == 2 then
						regs:insert('v'..(argIndex[i]+1))
					end
				end

				if #regs <= 4 then
					code:insert(table{
						'invoke-direct',
						getJNISig(classpath),
						ctorFwdMethodName,
						getJNISig(sig),
						'v0',	-- this
					}:append(regs))
				else
					error'TODO invoke-direct/range'
				end
				code:insert{'return-void'}	-- no return type
			else
				code:insert{'aload_0'}		-- push 'this' onto the stack
				-- TODO This always calls the parent-class's <init>().  what about dif ctor sigs?
				code:insert{'invokespecial', parentClass, '<init>', '()V'}

				-- load all args
				code:insert{'aload_0'}
				for i=1,sigNumArgs do		-- 1-based argument index
					local primInfo = infoForPrims[sig[i+1]]
					local argOpcode = primInfo and primInfo.asmClassLoadOp or 'aload'	-- default ot all non-prims: Object

					local localVarIndex = argIndex[i]
					if localVarIndex < 4 then
						-- aload, iload, etc have 0123 as separate commands:
						code:insert{argOpcode..'_'..localVarIndex}
					else
						code:insert{argOpcode, localVarIndex}
					end
				end

				-- call our native fwd method
				code:insert{
					'invokevirtual',
					classpath,
					ctorFwdMethodName,
					getJNISig(sig),
				}
				code:insert{'return'}	-- no return type
			end

			--[[ default.  i know i should let this fall back on package-scope i.e. no public/private/protected.  meh.
			if ctor.isPublic == nil
			and ctor.isPrivate == nil
			and ctor.isProtected == nil
			then
				ctor.isPublic = true
			end
			--]]

			ctor.value = nil
			ctor.code = code

			--ctor.maxStack = 6	-- always? or will it be sig dependent? esp for long/double?
			ctor.maxLocals = localVarIndex

			asmClassArgs.methods:insert(ctor)
		end
	end

	if args.methods then
		for key,method in pairs(args.methods) do
			if type(key) == 'string' then
				if type(method) == 'function' then
					method = {
						name = key,
						value = method,
						isPublic = true,
					}
				else
					assert.type(method, 'table')
					if not method.name then
						method.name = key
					end
				end
			end
			assert.type(method, 'table')

			method.isNative = true

			--[[ default.  i know i should let this fall back on package-scope i.e. no public/private/protected.  meh.
			if method.isPublic == nil
			and method.isPrivate == nil
			and method.isProtected == nil
			then
				method.isPublic = true
			end
			--]]

			method.code = nil
			asmClassArgs.methods:insert(method)

			local func = assert.index(method, 'value')
			fixMethodSig(method)
			local nativeMethod = nativeMethods:emplace_back()
			nativeMethod.name = method.name
			nativeMethod.signature = method.jniSig	-- built in fixMethodSig()

			if method.newLuaState then
				assert.type(func, 'function', "newLuaState requires a Lua function")

				-- Make a new lite-thread and sub-lua-state for this method
				-- TODO should it be one per method or one per class?
				-- TODO some kind of better mix and match of sub-lua-states and methods.
				-- another TODO ... this will be one sub-Lua-state per-class, which means it will be shared with all objects ...
				local thread = LiteThread{

					-- make the threadFuncTypeName match those for JNI java.lang.Runnable's run() native signature
					threadFuncTypeName = getCFuncTypeForSig(method.sig, method.isStatic),

					-- callback prefix code.
					-- I need to require java.ffi.jni in here,
					--  or the ffi.cast(threadFuncTypeName) won't work
					init = function(thread)
						-- have to define this before pushing data of its cdata type into the new Lua state...
						thread.lua[[
-- this is needed for the ffi.cast threadFuncTypeName declaration
require 'java.ffi.jni'
]]

						thread.lua([[
local func,
	jvmPtr,
	sig,
	isStatic,
	classpath,
	usingAndroidJNI = ...

-- rebuild the JavaVM here, once
-- but I can't rebuild it without the jnienv
-- and the vm won't create a new jnienv until a new thread is made
-- and the new thread won't be made until after the method call happens
-- and we're still in init
-- so instead for now here just make a function for creating it or returning it
local reg = debug.getregistry()
reg.java_callback = func
reg.java_method = {sig=sig, isStatic=isStatic}
reg.java_classpath = classpath
reg.java_getJVM = function(envPtr)
	local reg = debug.getregistry()
	if not reg.java_jvm then
		reg.java_jvm = require 'java.vm'{
			ptr = jvmPtr,
			usingAndroidJNI = usingAndroidJNI,
			jniEnv = {
				ptr = envPtr,
			},
		}
	end
	return reg.java_jvm
end
]],
	func,	-- convert to bytecode and pass into the child Lua state:
	env._vm._ptr,
	method.sig,
	method.isStatic,
	classpath,
	env._usingAndroidJNI)

					end,
					-- callback function:
					func = function(envPtr, thisOrClass, ...)
						-- THIS IS RUN ON A SEPARATE THREAD AND IN THE CHILD LUA STATE

						-- rebuild env from envPtr in case it's on a new thread
						-- but we can use the same jvm pointer
						-- hmm possible TODO is
						-- 1) cache the JNIEnv and use the 1st copy created always
						-- 2) cache it per tonumber(envPtr) or tostring(envPtr)
						-- 3) always rebuild the JavaVM and JNIEnv
						-- 4) cache the JavaVM like I'm doing now
						local reg = debug.getregistry()
						local method = reg.java_method
						local classpath = reg.java_classpath
						local jvm = reg.java_getJVM(envPtr)
						local func = reg.java_callback
						local env = jvm.jniEnv
						local sig = method.sig

						-- rebuild args

						if method.isStatic then
							-- TODO this method but also with a class helper?
							thisOrClass = env:_fromJClass(thisOrClass)
						else
							thisOrClass = env:_javaToLuaArg(thisOrClass, classpath)
						end

						local result = func(
							env,
							thisOrClass,
							env:_javaToLuaArgs(2, sig, ...)
						)

						if sig[1] == 'void' then return end
						if result == nil then return nil end

						return env:_luaToJavaArg(result, sig[1])
					end,
				}

				-- do this but after done running
				-- or TODO somehow allow the caller access to it
				--thread:showErr()

				-- save the thread so it doesn't collect
				closures:insert{thread=thread}
				usingNewLuaState = true

				-- use the thread's wrapper's function pointer
				func = thread.funcptr
			end


			if type(func) == 'cdata' then
				-- assume whoever passes this knows what they are doing...
				nativeMethod.fnPtr = ffi.cast('void*', func)
--DEBUG:io.stderr:write("!!! DANGER !!! I just got rid of the translation layer for cdata function pointers...\n")
			else
				local sig = method.sig

				-- the wrapper should be similar to the ctor implementaiton but without the Object[] and boxing/unboxing
				local wrapper = function(envPtr, thisOrClass, ...)
					-- this wrapper will assume we are using the same JNIEnv i.e. on same-state
					-- if you want a new state, use the 'newLuaState' flag which is handled above
					if method.isStatic then
						-- TODO this method but also with a class helper?
						thisOrClass = env:_fromJClass(thisOrClass)
					else
						thisOrClass = env:_javaToLuaArg(thisOrClass, classpath)
					end

--DEBUG:print('wrapper sig', require 'ext.tolua'(sig))
--DEBUG:print('wrapper arg type', type((...)))
--DEBUG:print('wrapper args', ...)
					local result = func(
						thisOrClass,
						env:_javaToLuaArgs(2, sig, ...)
					)

					if sig[1] == 'void' then return end
					if result == nil then return nil end

					return env:_luaToJavaArg(result, sig[1])
				end

				local cfuncType = getCFuncTypeForSig(method.sig, method.isStatic)
--DEBUG:print('got c sig', cfuncType)
				-- cfuncType will tell LuaJIT how to translate arguments to JNI types
				local closure = ffi.cast(cfuncType, wrapper)

				closures:insert{
					wrapper = wrapper,
					closure = closure,
					func = func,
					name = method.name,
					sig = method.jniSig,
				}

				nativeMethod.fnPtr = ffi.cast('void*', closure)
			end
		end
	end
	if args.returnASMArgsOnly then return asmClassArgs end

	local asm
	if isAndroid then
		local JavaASMDex = require 'java.asmdex'
		asm = JavaASMDex(asmClassArgs)
	else
		local JavaASMClass = require 'java.asmclass'
		asm = JavaASMClass(asmClassArgs)
	end
	if args.returnASMOnly then return asm end

	local cl = env:_loadClass(asm)
	if not cl then return nil, "failed to define class" end

	if #nativeMethods > 0 then
--DEBUG:print('registering', #nativeMethods)
--DEBUG:for i=0,#nativeMethods-1 do
--DEBUG:	local n = nativeMethods.v + i
--DEBUG:	print(n.fnPtr, ffi.string(n.name), ffi.string(n.signature))
--DEBUG:end
		env:_registerNatives(cl._ptr, nativeMethods.v, #nativeMethods)
	end

	-- in case we used newLuaState ...
	-- This is a helper function that is assigned to the JavaClass but only accessible from the thread/JNIEnv of its creation
	-- which shows any errors that might have been invoked on the sub-Lua-state in the new thread.
	if usingNewLuaState then
		rawset(cl, '_showLuaThreadErrors', function(self)
			for _,cls in ipairs(closures) do
				if cls.thread then
					cls.thread:showErr()
				end
			end
		end)
	end

	return cl
end

return setmetatable(M, {
	__call = M.run,
})
