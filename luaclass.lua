--[[
auto-gen java bytecode at runtime to make a glue-class whose methods point to Lua functions
uses java/nativecallback.lua to do its LuaJIT->Java->LuaJIT, but honestly we're getting to the point where I can just inline that myself...
--]]

local ffi = require 'ffi'
local assert = require 'ext.assert'
local table = require 'ext.table'
local JavaClass = require 'java.class'
local JavaASMClass = require 'java.asmclass'
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
			sig =
			isPrivate =
			isPublic =
		},
		...
	}
	methods = (optional) {
		{
			name =
			sig = table, 1st is return value, rest are arguments,
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

	local NativeCallback = require 'java.nativecallback'(J)

	local classname = args.name
	if not classname then
		classname = M.classnameBase
			..bit.tohex(ffi.cast('uint64_t', J._ptr), bit.lshift(ffi.sizeof'intptr_t', 1))
			..'_'..uniqueNameCounter
		uniqueNameCounter = uniqueNameCounter + 1
	end
	local classnameSlashSep = classname:gsub('%.', '/')

	local parentClass = args.extends or 'java.lang.Object'
	local parentClassSlashSep = parentClass:gsub('%.', '/')

	local interfaces = table()
	for i,name in ipairs(args.implements or {}) do
		if type(name) == 'string' then
		elseif type(name) == 'table' then
			if not require 'java.class':isa(name) then
				error(".interfaces["..i.."] expects a string or a JavaClass")
			end
			name = name._classpath
		else
			error(".interfaces["..i.."] expects a string or a JavaClass")
		end
		interfaces[i] = name:gsub('%.', '/')
	end

	local closures = table()	-- to-free
	M.savedClosures[classname] =  closures


	local asmClassArgs = {
		version = 0x41,
		isPublic = true,
		isSuper = true,
		thisClass = classnameSlashSep,
		superClass = parentClassSlashSep,
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

			field.sig = getJNISig((
				assert.type(assert.index(field, 'sig'), 'string')
			))

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

		-- special for ctors, call parent
		if method.name == '<init>' then
			code:insert{'aload_0'}
			code:insert{'invokespecial', parentClassSlashSep, '<init>', '()V'}	-- TODO this always calls the parent-class's <init>().  what about dif args?
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

		-- now native callback will get ...
		-- 1) a funcptr from a closure
		code:insert{'ldc2_w', 'long', ffi.cast('jlong', funcptr)}

		-- 2) an Object[] of {this, ... rest of args of the method}
		local sigNumArgs = #sig-1
--DEBUG:print('sigNumArgs', sigNumArgs)
		code:insert{'bipush', sigNumArgs+1}		-- +1 for 'this' (TODO static)
		code:insert{'anewarray', 'java/lang/Object'}

		-- set args[0] = this
		-- TODO if it's static, what to do?  pass nothing?  pass the JavaObject of the java.lang.Class?
		code:insert{'dup'}
		code:insert{'iconst_0'}
		code:insert{'aload_0'}
		code:insert{'aastore'}

		local baseArg = method.isStatic and 0 or 1		-- to skip 'this' ... right?
		if sigNumArgs > 0 then
			local localVarIndex = method.isStatic and 0 or 1	-- right?
			for i=0,sigNumArgs-1 do		-- 0-based argument index
				code:insert{'dup'}

				local argIndex = i + baseArg
				if argIndex <= 5 then
					code:insert{'iconst_'..argIndex}
				else
					code:insert{'bipush', argIndex}
				end

				local argSig = sig[i+2]
				local primInfo = infoForPrims[argSig]

				local argOpcode = primInfo and 'iload' or 'aload'
				code:insert{argOpcode, localVarIndex}
				if primInfo then
					local boxedTypeSlashSep = primInfo.boxedType:gsub('%.', '/')
					code:insert{
						'invokestatic',
						boxedTypeSlashSep,
						'valueOf',
						getJNISig{primInfo.boxedType, primInfo.name}
					}
				end

				code:insert{'aastore'}

				if argSig == 'long' or argSig == 'double' then
					localVarIndex = localVarIndex + 2
				else
					localVarIndex = localVarIndex + 1
				end
			end
		end

		-- call `NativeCallback.run(funcptr, Object[]{this, args...})`
		code:insert{
			'invokestatic',
			NativeCallback._classpath:gsub('%.', '/'),
			assert(NativeCallback._runMethodName),
			'(JLjava/lang/Object;)Ljava/lang/Object;',
		}

		-- now on the stack is a java.lang.Object from NativeCallback.run()
		-- next, convert it depending on this function's return type
--DEBUG:print('returnType', returnType)
		local primInfo = infoForPrims[returnType]
		if returnType == 'void' then
			code:insert{'return'}
		elseif primInfo then
			-- cast to BoxedType
			local boxedTypeSlashName = primInfo.boxedType:gsub('%.', '/')
			code:insert{'checkcast', boxedTypeSlashName}
			code:insert{
				'invokevirtual',
				boxedTypeSlashName,
				primInfo.name..'Value',
				getJNISig{primInfo.name},
			}
			code:insert{primInfo.returnOp}
		else
			code:insert{
				'checkcast',
				(returnType:gsub('%.', '/')),
			}
			code:insert{'areturn'}
		end

		if method.isPublic == nil then method.isPublic = true end
		method.value = nil
		method.sig = jniSig
		method.code = code

		method.maxStack = 10	-- honestly I don't have a clue

		method.maxLocals =
			baseArg 	-- +1 for 'this' for non-static ... ?
			+ 1			-- +1 for the new Object[] ... ?
			+ (table.sub(sig, 2):mapi(function(sigi)
				-- max locals ... wait, locals include args right?
				-- so any sig that is double or long needs 2, otherwise 1?
				return (sigi == 'long' or sigi == 'double') and 2 or 1
			end):sum() or 0)

		asmClassArgs.methods:insert(method)
	end

	local srcCtors = args.ctors
	if not srcCtors or #srcCtors == 0 then
		asmClassArgs.methods:insert{
			isPublic = true,
			name = '<init>',
			sig = '()V',
			maxStack = 1,
			maxLocals = 1,

			-- provide a default ctor, no need for closure or callback
			code = [[
aload 0
invokespecial ]]..parentClassSlashSep..[[ <init> ()V
return
]],
		}
	else
		for _,ctor in ipairs(args.ctors) do
			ctor.name = '<init>'
			ctor.sig = ctor.sig or {'void'}
			ctor.sig[1] = 'void'
			ctor.isStatic = false
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

	return J:_defineClass(JavaASMClass(asmClassArgs))
end

return setmetatable(M, {
	__call = M.run,
})
