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


local uniqueNameCounter = 1

table.union(infoForPrims.boolean, {
	returnOp = 'ireturn',
})
table.union(infoForPrims.char, {
	returnOp = 'ireturn',
})
table.union(infoForPrims.byte, {
	returnOp = 'ireturn',
})
table.union(infoForPrims.short, {
	returnOp = 'ireturn',
})
table.union(infoForPrims.int, {
	returnOp = 'ireturn',
})
table.union(infoForPrims.long, {
	returnOp = 'lreturn',
})
table.union(infoForPrims.float, {
	returnOp = 'freturn',
})
table.union(infoForPrims.double, {
	returnOp = 'dreturn',
})


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
--]]
function M:run(args)
	local env = assert.index(args, 'env')
	local isAndroid = env._usingAndroidJNI
	local NativeCallback = require 'java.nativecallback'(env)

	local classpath = args.name
	if not classpath then
		classpath = M.classnameBase
			..bit.tohex(ffi.cast('uint64_t', env._ptr), bit.lshift(ffi.sizeof'intptr_t', 1))
			..'_'..uniqueNameCounter
		uniqueNameCounter = uniqueNameCounter + 1
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
		isSuper = true,				-- .class only
		thisClass = classpath,
		superClass = parentClass,
		interfaces = interfaces,
		fields = table(),
		methods = table(),
	}

	local nativeMethods = vector'JNINativeMethod'

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
				}
			end
			assert.type(field, 'table')
			if field.isPublic == nil then field.isPublic = true end

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

	-- this is currently only used for ctors
	-- TODO give ctors a native method like I do for all other methods below, and get rid of this cuz its bloated and has lots of asm
	local function buildLuaWrapperMethod(method)
		fixMethodSig(method)
		local sig = method.sig
		local returnType = sig[1]

		-- map from arg # (1-based) to stack or register index # (0-based)
		local argIndex = table()
		-- in android do static methods have a 'this' equivalent, like 'class', like the JNI static calls do?
		local maxArgIndex = method.isStatic and 0 or 1
		for i=2,#sig do
			local sigi = sig[i]
			argIndex[i-1] = maxArgIndex
			maxArgIndex = maxArgIndex + ((sigi == 'long' or sigi == 'double') and 2 or 1)
		end
--DEBUG:print('method', method.name, require 'ext.tolua'(method.sig))
--DEBUG:print('argIndex', require 'ext.tolua'(argIndex))

		local sigNumArgs = #sig-1
--DEBUG:print('sigNumArgs', sigNumArgs)
		local argArraySize = sigNumArgs
			-- +1 for 'this' unless it's static
			+ (method.isStatic and 0 or 1)

		--[[
		me learning android
		maybe this is wrong
		but
		maxRegs = # used for calling out (regsOut) ... at the beginning
			+ any local use only regs ... go next
			+ # used for being called (regIn, determined by arg types + static or not) ... go at the end
		--]]
		if isAndroid then
			-- v2 for Object[] list
			-- v0 & v1 for funcptr
			method.regsOut = 3
			-- v3 = local for array index
			-- so that means 'this' is at v4
			-- and the rest of the args are past v3 ...
			-- ... right?
			method.regsIn = maxArgIndex
			local numLocals = 1
			method.maxRegs = method.regsOut + numLocals + method.regsIn
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
		if method.name == '<init>' then
			if isAndroid then
				code:insert{'invoke-direct', getJNISig(parentClass), '<init>', '()V', 'v4'}	-- v4 has 'this'
			else
				code:insert{'aload_0'}		-- push 'this' onto the stack
				-- TODO This always calls the parent-class's <init>().  what about dif args?
				code:insert{'invokespecial', parentClass, '<init>', '()V'}
			end
		end

		local func = assert.index(method, 'value')
		-- if it's cdata then use it as-is
		local funcptr
		if type(func) == 'cdata' then
		-- if it's a function then wrap it in a conversion layer
			funcptr = func
		elseif type(func) == 'function' then
			local wrapper = function(args)
--DEBUG:print('wrapper args', args)
				local result
--DEBUG:print('wrapper calling sig', require 'ext.tolua'(sig))
				if args ~= nil then
					-- args should be Object[] always, and for members it will have args[0]==this
					args = env:_javaToLuaArg(args, 'java.lang.Object[]')
					result = func(args:_unpack())
				else
					result = func()
				end
				if returnType == 'void' then
					return nil
				else
					-- return a boxed type
					local primInfo = infoForPrims[returnType]
					local boxedSig = primInfo and primInfo.boxedType or returnType
--DEBUG:print('converting from', result, type(result), 'to sig', returnType, 'to (boxed?)', boxedSig)
					-- will be a java.lang.Object here no matter what
					-- so the jobject(jobject) funcptr sig can handle it
					return env:_luaToJavaArg(result, boxedSig)
				end
			end
			local closure = ffi.cast('void*(*)(void*)', wrapper)
			closures:insert(closure)
			funcptr = closure
		else
			error("idk how to handle method value of type "..type(func))
		end

		-- now native callback will get ...
		-- 1) a funcptr from a closure
		if isAndroid then
			-- v4 has 'this' ... or 'class'? or null?
			-- v5... have all the arguments ....
			-- v0&v1 get jlong funcptr

			-- TODO should I add a type arg to .dex const-wide?
			--  or should I change .class to detect and remove the type arg?
			code:insert{'const-wide', 'v0', ffi.cast('jlong', funcptr)}
		else
			-- stack:
			code:insert{'ldc2_w', 'long', ffi.cast('jlong', funcptr)}
			-- stack: long funcptr
		end

		-- 2) an Object[] of {this, ... rest of args of the method}
		if isAndroid then
			if argArraySize < 8 then
				code:insert{'const/4', 'v2', argArraySize}
			else
				assert(argArraySize < 128, 'more plz')
				code:insert{'const/8', 'v2', argArraySize}
			end
			-- v2 gets Object[] args
			code:insert{'new-array', 'v2', 'v2', '[java/lang/Object;'}
		else
			-- stack: [Object this], long funcptr
			pushConstInt(argArraySize)
			code:insert{'anewarray', 'java/lang/Object'}
			-- stack: long funcptr, Object[] args
		end

		-- set args[0] = this
		-- if it's static, what to do?
		-- TODO pass the JavaObject of the java.lang.Class?
		local localVarIndex = 0
		local argArrayIndex = 0
		if isAndroid then
			localVarIndex = 4	-- pass our 3 outgoing and 1 local
		end
		-- to skip 'this' ... right?
		if not method.isStatic then
			if isAndroid then
				--v3 = argArrayIndex
				code:insert{'const', 'v3', argArrayIndex}
				code:insert{
					'aput-object',
					'v'..localVarIndex,		-- reg with value to push: 'this'
					'v2',	-- reg with array
					'v3',	-- reg with array index
				}
			else
				code:insert{'dup'}
				-- stack: funcptr, args, args
				pushConstInt(argArrayIndex)				-- array index ...?
				-- stack: funcptr, args, args, argArrayIndex
				code:insert{'aload_'..localVarIndex}	-- local index (0 for 'this')
				-- stack: funcptr, args, args, argArrayIndex, this
				code:insert{'aastore'}
				-- stack: funcptr, args ... args[argArrayIndex] = this
			end
			localVarIndex = localVarIndex + 1	-- start us at 1
			argArrayIndex = argArrayIndex + 1
		end

		if sigNumArgs > 0 then
			for i=0,sigNumArgs-1 do		-- 0-based argument index

				local argSig = sig[i+2]
				local primInfo = infoForPrims[argSig]

				if isAndroid then
					if primInfo then
						-- call 'valueOf' to box before storing
						code:insert{
							'invoke-static',
							getJNISig(primInfo.boxedType),					-- class
							'valueOf',										-- method name
							getJNISig{primInfo.boxedType, primInfo.name},	-- signature
							'v'..localVarIndex,								-- argument
							(argSig == 'long' or argSig == 'double') and 'v'..(localVarIndex+1) or nil
						}
						code:insert{
							'move-result-object',
							'v'..localVarIndex,			-- can I do it destructively and overwrite the argument?
						}
					end
					--v3 = argArrayIndex
					code:insert{'const', 'v3', argArrayIndex}
					code:insert{
						'aput-object',
						'v'..localVarIndex,		-- reg with value to push: local #localVarIndex
						'v2',					-- reg with array
						'v3',					-- reg with array index
					}
				else
					code:insert{'dup'}
					-- stack: funcptr, args, args
					pushConstInt(argArrayIndex)
					-- stack: funcptr, args, args, argArrayIndex

					local argOpcode
					if primInfo then
						if argSig == 'long' then
							argOpcode = 'lload'
						elseif argSig == 'double' then
							argOpcode = 'dload'
						elseif argSig == 'float' then
							argOpcode = 'fload'
						else	-- all other prims: int
							argOpcode = 'iload'
						end
					else	-- all non-prims: Object
						argOpcode = 'aload'
					end

					if localVarIndex < 4 then
						-- aload, iload, etc have 0123 as separate commands:
						code:insert{argOpcode..'_'..localVarIndex}
					else
						code:insert{argOpcode, localVarIndex}
					end
					-- stack: funcptr, args, args, argArrayIndex, local[localVarIndex]

					if primInfo then
						code:insert{
							'invokestatic',
							primInfo.boxedType,
							'valueOf',
							getJNISig{primInfo.boxedType, argSig}
						}
					end
					code:insert{'aastore'}
					-- stack: funcptr, args ... args[argArrayIndex] = local[localVarIndex]
				end

				if argSig == 'long' or argSig == 'double' then
					localVarIndex = localVarIndex + 2
				else
					localVarIndex = localVarIndex + 1
				end
				argArrayIndex = argArrayIndex + 1
			end
		end

		-- call `NativeCallback.run(funcptr, Object[]{this, args...})`
		local callbackClassPath = NativeCallback._classpath
		local runMethodName = assert(NativeCallback._runMethodName)
		local runMethodSig = '(JLjava/lang/Object;)Ljava/lang/Object;'
		if isAndroid then
			code:insert{
				'invoke-static',
				getJNISig(callbackClassPath),
				runMethodName,
				runMethodSig,
				'v0',		-- jlong funcptr
				'v1',
				'v2'		-- Object[] args index
			}
		else
			code:insert{
				'invokestatic',
				callbackClassPath,
				runMethodName,
				runMethodSig,
			}
		end

		-- now on the stack is a java.lang.Object from NativeCallback.run()
		-- next, convert it depending on this function's return type
--DEBUG:print('returnType', returnType)
		local primInfo = infoForPrims[returnType]
		if returnType == 'void' then
			code:insert{'return-void'}	-- aliased on .class to 'return'
		elseif primInfo then
			if isAndroid then
				-- cast to boxed type
				code:insert{'move-result-object', 'v0'}
				code:insert{'check-cast', 'v0', getJNISig(primInfo.boxedType)}
				-- convert back to value
				code:insert{
					'invoke-virtual',
					getJNISig(primInfo.boxedType),
					primInfo.name..'Value',
					getJNISig{primInfo.name},
					'v0',
				}
				if primInfo.name == 'long' or primInfo.name == 'double' then
					code:insert{'move-result-wide', 'v0'}
					code:insert{'return-wide', 'v0'}
				else
					code:insert{'move-result', 'v0'}
					code:insert{'return', 'v0'}
				end
			else
				-- cast to boxed type
				code:insert{'checkcast', primInfo.boxedType}
				-- convert back to value
				code:insert{
					'invokevirtual',
					primInfo.boxedType,
					primInfo.name..'Value',
					getJNISig{primInfo.name},
				}
				code:insert{primInfo.returnOp}
			end
		else
			if isAndroid then
				code:insert{'move-result-object', 'v0'}
				code:insert{
					'check-cast',
					'v0',
					getJNISig(returnType)
				}
				code:insert{'return-object', 'v0'}
			else
				code:insert{
					'checkcast',
					(returnType:gsub('%.', '/')),
				}
				code:insert{'areturn'}
			end
		end

		if method.isPublic == nil then method.isPublic = true end
		method.value = nil
		method.code = code

		--method.maxStack = 6	-- always? or will it be sig dependent? esp for long/double?
		method.maxLocals = localVarIndex

		asmClassArgs.methods:insert(method)
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
		for _,ctor in ipairs(args.ctors) do
			if type(ctor) == 'function' then
				ctor = {
					value = ctor,
				}
			end
			ctor.name = '<init>'
			ctor.sig = ctor.sig or {'void'}
			ctor.sig[1] = 'void'		-- ctor must return void
			ctor.isStatic = false		-- ctor must not be static
			ctor.isConstructor = true	-- .dex only
			buildLuaWrapperMethod(ctor)
		end
	end

	if args.methods then
		for key,method in pairs(args.methods) do
			if type(key) == 'string' then
				if type(method) == 'function' then
					method = {
						name = key,
						value = method
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
			if method.isPublic == nil then method.isPublic = true end
			method.code = nil
			asmClassArgs.methods:insert(method)

			local func = assert.index(method, 'value')
			fixMethodSig(method)
			local nativeMethod = nativeMethods:emplace_back()
			nativeMethod.name = method.name
			nativeMethod.signature = method.jniSig	-- built in fixMethodSig()

			local function jniTypeForSig(s)
				if s == 'void 'then return 'void' end
				if s == 'java.lang.String' then return 'jstring' end
				local primInfo = infoForPrims[s]
				if primInfo then return 'j'..s end
				return 'jobject'
			end

			local function getCFuncTypeForSig(sig)
				-- build wrapper for args here:
				local jniCSig = table()
				jniCSig:insert(jni.JNIEXPORT..' ')
				jniCSig:insert(jniTypeForSig(sig[1]))
				jniCSig:insert(' '..jni.JNICALL)
				jniCSig:insert'(*)(JNIEnv*'	-- function args begin
				if method.isStatic then
					jniCSig:insert', jclass'	-- calling class
				else
					jniCSig:insert', jobject'	-- this
				end
				for i=2,#sig do
					jniCSig:insert(', '..jniTypeForSig(sig[i]))
				end
				jniCSig:insert')'		-- function args end
--DEBUG:print('for method', method.isStatic and 'static' or '', 'sig', require 'ext.tolua'(method.sig))
				return jniCSig:concat()
			end


			if method.newLuaState then
				assert.type(func, 'function', "newLuaState requires a Lua function")

				-- Make a new lite-thread and sub-lua-state for this method
				-- TODO should it be one per method or one per class?
				-- TODO some kind of better mix and match of sub-lua-states and methods.
				-- another TODO ... this will be one sub-Lua-state per-class, which means it will be shared with all objects ...
				local thread = LiteThread{

					-- make the threadFuncTypeName match those for JNI java.lang.Runnable's run() native signature
					threadFuncTypeName = getCFuncTypeForSig(method.sig),

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
	classpath = ...

-- rebuild the JavaVM here, once
-- but I can't rebuild it without the jnienv
-- and the vm won't create a new jnienv until a new thread is made
-- and the new thread won't be made until after the method call happens
-- and we're still in init
-- so instead for now here just make a function for creating it or returning it
local reg = debug.getregistry()
reg.java_callback = func
reg.method = {sig=sig, isStatic=isStatic}
reg.classpath = classpath
reg.getJVM = function(envPtr)
	if not reg.jvm then
		reg.jvm = require 'java.vm'{
			ptr = jvmPtr,
			jniEnv = {
				ptr = envPtr,
			},
		}
	end
	return reg.jvm
end

]],
	func,	-- convert to bytecode and pass into the child Lua state:
	env._vm._ptr,
	method.sig,
	method.isStatic,
	classpath)

					end,
					-- callback function:
					func = function(envPtr, thisOrClass, ...)
						-- THIS IS RUN ON A SEPARATE THREAD AND IN THE CHILD LUA STATE

						-- rebuild env from envPtr in case it's on a new thread
						-- but we can use the same jvm pointer
						local reg = debug.getregistry()
						local method = reg.method
						local classpath = reg.classpath
						local jvm = reg.getJVM(envPtr)
						local func = reg.java_callback
						local env = jvm.jniEnv
						local sig = method.sig
						local table = require 'ext.table'

						-- rebuild args

						if method.isStatic then
							-- TODO this method but also with a class helper?
							thisOrClass = env:_fromJClass(thisOrClass)
						else
							thisOrClass = env:_javaToLuaArg(thisOrClass, classpath)
						end
						local args = table.pack(...)
						for i=1,args.n do
							args[i] = env:_javaToLuaArg(args[i], sig[i+1])
						end

						local result = func(env, thisOrClass, args:unpack(1, args.n))

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
					--[[ this is somewhat thread-safe since JNI will call the C func with a new envPtr when we are crossing threads
					-- but I've already got java/saferunnable.lua for handling that, with its new Lua state.
					--  (it is why method.value can accept cdata)
					-- so here I wont do this and I'll just use closure env
					local env = JNIEnv{ptr=envPtr, vm=env._vm, usingAndroidJNI=env._usingAndroidJNI}
					--]]
					-- lazy for now while I debug this:
					if method.isStatic then
						-- TODO this method but also with a class helper?
						thisOrClass = env:_fromJClass(thisOrClass)
					else
						thisOrClass = env:_javaToLuaArg(thisOrClass, classpath)
					end
					local args = table.pack(...)
					for i=1,args.n do
						args[i] = env:_javaToLuaArg(args[i], sig[i+1])
					end

					local result = func(thisOrClass, args:unpack(1, args.n))

					if sig[1] == 'void' then return end
					if result == nil then return nil end

					return env:_luaToJavaArg(result, sig[1])
				end

				local cfuncType = getCFuncTypeForSig(method.sig)
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

	local cl
	if isAndroid then
		local JavaASMDex = require 'java.asmdex'
		cl = env:_defineClass(JavaASMDex(asmClassArgs))
	else
		local JavaASMClass = require 'java.asmclass'
		cl = env:_defineClass(JavaASMClass(asmClassArgs))
	end
	if not cl then return nil, "failed to define class" end

	if #nativeMethods > 0 then
--DEBUG:print('registering', #nativeMethods)
--DEBUG:for i=0,#nativeMethods-1 do
--DEBUG:	local n = nativeMethods.v + i
--DEBUG:	print(n.fnPtr, ffi.string(n.name), ffi.string(n.signature))
--DEBUG:end
		env._ptr[0].RegisterNatives(env._ptr, cl._ptr, nativeMethods.v, #nativeMethods)
	end

	return cl
end

return setmetatable(M, {
	__call = M.run,
})
