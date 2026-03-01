--[[
auto-gen java bytecode at runtime to make a glue-class whose methods point to Lua functions

Still depends on io_github_thenumbernine_NativeCallback.c ...
--]]

local ffi = require 'ffi'
local assert = require 'ext.assert'
local table = require 'ext.table'
local JavaClass = require 'java.class'
local JavaClassData = require 'java.classdata'
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
	interfaces = (optional) list-of-interfaces to use
	fields = (optional) {
		{
			name =
			sig = string of dot-separated java type (primitive, class, array, etc)
			isStatic =
			isPublic =
			isPrivate =
			...
		},
		...
	}
	ctors = (optional) {
		{
			func = Lua callback function
			sig =
			isPrivate =
			isPublic =
		},
		...
	}
	methods = (optional) {
		{
			func = Lua callback function
			name =
			sig = table, 1st is return value, rest are arguments,
			isVarArg
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
	for i,name in ipairs(args.interfaces or {}) do
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

	local classDataArgs = {
		version = 0x41,
		isPublic = true,
		isSuper = true,
		thisClass = classnameSlashSep,
		superClass = parentClassSlashSep,
		interfaces = interfaces,
		fields = table(args.fields):mapi(function(field)
			return {
				isPublic = true,
				name = assert.type(assert.index(field, 'name'), 'string'),
				sig = getJNISig((assert.type(assert.index(field, 'sig'), 'string')))
			}
		end),
		methods = table(),
	}

	local function buildLuaWrapperMethod(method)
		local sig = method.sig or {}
		sig[1] = sig[1] or 'void'
		local returnType = sig[1]
	
		local code = table()
		local classDataMethod = {
			isPublic = true,
			name = method.name,
			sig = getJNISig(sig),
			code = code,
		}

		-- special for ctors, call parent
		if method.name == '<init>' then
			code:insert{'aload_0'}
			code:insert{'invokespecial', parentClassSlashSep, '<init>', '()V'}	-- TODO this always calls the parent-class's <init>().  what about dif args?
		end

		local func = assert.index(method, 'func')
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
			error("idk how to handle func of type "..type(func))
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

		if sigNumArgs > 0 then
			local localVarIndex = 1
			for i=0,sigNumArgs-1 do		-- 0-based argument index
				code:insert{'dup'}

				-- write to args[i+1] to skip 'this'
				if i+1 <= 5 then
					code:insert{'iconst_'..(i+1)}
				else
					code:insert{'bipush', i+1}
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

		classDataMethod.maxStack = 10
		classDataMethod.maxLocals =
			1 + (table.sub(sig, 2):mapi(function(sigi)
				-- max locals ... wait, locals include args right?
				-- so any sig that is double or long needs 2, otherwise 1?
				return (sigi == 'long' or sigi == 'double') and 2 or 1
			end):sum() or 0)
	
		classDataArgs.methods:insert(classDataMethod)
	end

	local srcCtors = args.ctors
	if not srcCtors or #srcCtors == 0 then
		local code = table()
		local classDataMethod = {
			isPublic = true,
			name = '<init>',
			sig = '()V',
			code = code,
			maxStack = 3,
			maxLocals = 1,
		}
		classDataArgs.methods:insert(classDataMethod)
		-- provide a default ctor, no need for closure or callback
		code:insert{'aload', 0}
		code:insert{'invokespecial', parentClassSlashSep, '<init>', '()V'}
		code:insert{'return'}
	else
		for _,ctor in ipairs(args.ctors) do
			ctor.name = '<init>'
			ctor.sig = ctor.sig or {'void'}
			ctor.sig[1] = 'void'
			ctor.isStatic = false
			buildLuaWrapperMethod(ctor)
		end
	end

	for _,method in ipairs(args.methods or {}) do
		buildLuaWrapperMethod(method)
	end

	return J:_defineClass(JavaClassData(classDataArgs))
end

return setmetatable(M, {
	__call = M.run,
})
