--[[
auto-gen java bytecode at runtime to make a glue-class whose methods point to Lua functions
uses java/nativecallback.lua to do its LuaJIT->Java->LuaJIT, but honestly we're getting to the point where I can just inline that myself...
--]]

local ffi = require 'ffi'
local assert = require 'ext.assert'
local table = require 'ext.table'
local JavaClass = require 'java.class'
local getJNISig = require 'java.util'.getJNISig
local infoForPrims = require 'java.util'.infoForPrims

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
-- So I'll put them here with key = classname
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
	local J = assert.index(args, 'env')
	local isAndroid = J._usingAndroidJNI
	local NativeCallback = require 'java.nativecallback'(J)

	local classname = args.name
	if not classname then
		classname = M.classnameBase
			..bit.tohex(ffi.cast('uint64_t', J._ptr), bit.lshift(ffi.sizeof'intptr_t', 1))
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
	M.savedClosures[classname] =  closures


	local asmClassArgs = {
		version = 0x41,
		isPublic = true,
		isSuper = true,				-- .class only
		thisClass = classname,
		superClass = parentClass,
		interfaces = interfaces,
		fields = table(),
		methods = table(),
	}


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

	local function buildLuaWrapperMethod(method)
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
		local returnType = sig[1]
		local jniSig = getJNISig(sig)

		-- fun fact, defining toString() with a return type other than the java.lang.String makes the VM segfault
		-- adding extra args to toString() makes the VM give you a warning
		if method.name == 'toString'
		and jniSig ~= '()Ljava/lang/String;'
		then
			io.stderr:write'!!! WARNING !!! You are defining a class method toString() with an atypical signature.  In my experience the VM will segfault next, or just warn you if you are lucky.  Enjoy.\n'
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
				code:insert{'invoke-direct', getJNISig(parentClass), '<init>', '()V', 'v0'}
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
					args = J:_javaToLuaArg(args, 'java.lang.Object[]')
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
					return J:_luaToJavaArg(result, boxedSig)
				end
			end
			local closure = ffi.cast('void*(*)(void*)', wrapper)
			closures:insert(closure)
			funcptr = closure
		else
			error("idk how to handle method value of type "..type(func))
		end

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
		-- now native callback will get ...
		-- 1) a funcptr from a closure
		if isAndroid then
			-- v0 has 'this' ... or 'class'? or null?
			-- v1..v{N-1} have all the arguments ....

			-- v{N} & v{N+1} get jlong funcptr

			-- TODO should I add a type arg to .dex const-wide?
			--  or should I change .class to detect and remove the type arg?
			code:insert{'const-wide', 'v'..maxArgIndex, ffi.cast('jlong', funcptr)}
		else
			-- stack:
			code:insert{'ldc2_w', 'long', ffi.cast('jlong', funcptr)}
			-- stack: long funcptr
		end

		local sigNumArgs = #sig-1
--DEBUG:print('sigNumArgs', sigNumArgs)
		local argArraySize = sigNumArgs
			-- +1 for 'this' unless it's static
			+ (method.isStatic and 0 or 1)

		-- 2) an Object[] of {this, ... rest of args of the method}
		if isAndroid then
			-- v{N+2} gets Object[] args
			code:insert{
				'new-array',
				'v'..(maxArgIndex+2),
				argArraySize,
				'[java/lang/Object;',
			}
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
		-- to skip 'this' ... right?
		if not method.isStatic then
			if isAndroid then
				code:insert{
					'iput-object',
					'v'..localVarIndex,		-- value to push: 'this'
					'v'..(maxArgIndex+2),	-- array
					argArrayIndex,			-- array index
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
						}
						code:insert{
							'move-result-object',
							'v'..localVarIndex,			-- can I do it destructively and overwrite the argument?
						}
					end
					code:insert{
						'iput-object',
						'v'..localVarIndex,		-- value to push
						'v'..(maxArgIndex+2),	-- array
						argArrayIndex,
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
				callbackClassPath,
				runMethodName,
				runMethodSig,
				'v'..maxArgIndex,		-- jlong funcptr
				'v'..(maxArgIndex+2),	-- Object[] args index
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
				code:insert{'move-result-object', 'v1'}
				code:insert{'check-cast', 'v1', getJNISig(primInfo.boxedType)}
				-- convert back to value
				code:insert{
					'invoke-virtual',
					getJNISig(primInfo.boxedType),
					primInfo.name..'Value',
					getJNISig{primInfo.name},
				}
				if primInfo.name == 'long' or primInfo.name == 'double' then
					code:insert{'move-result-wide', 'v1'}
					code:insert{'return-wide', 'v1'}
				else
					code:insert{'move-result', 'v1'}
					code:insert{'return', 'v1'}
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
				code:insert{'move-result-object', 'v1'}
				code:insert{
					'check-cast',
					'v1',
					getJNISig(returnType)
				}
				code:insert{'return-object', 'v1'}
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
			ctor.name = '<init>'
			ctor.sig = ctor.sig or {'void'}
			ctor.sig[1] = 'void'
			ctor.isStatic = false
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
			buildLuaWrapperMethod(method)
		end
	end

	if isAndroid then
		local JavaASMDex = require 'java.asmdex'
		return J:_defineClass(JavaASMDex(asmClassArgs))
	else
		local JavaASMClass = require 'java.asmclass'
		return J:_defineClass(JavaASMClass(asmClassArgs))
	end
end

return setmetatable(M, {
	__call = M.run,
})
