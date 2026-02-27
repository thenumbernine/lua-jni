--[[
This is going to take a list of properties and Lua callbacks and pop out a new JavaClass.

It will depend on NativeCallback and Java-ASM
--]]
local ffi = require 'ffi'
local assert = require 'ext.assert'
local table = require 'ext.table'
local JavaClass = require 'java.class'
local getJNISig = require 'java.util'.getJNISig
local infoForPrims = require 'java.util'.infoForPrims

local uniqueNameCounter = 1

local alreadyInitd
local function initInfoForPrims(Opcodes)
	if alreadyInitd then return end
	alreadyInitd = true
	table.union(infoForPrims.boolean, {
		returnOp = Opcodes.IRETURN,
	})
	table.union(infoForPrims.char, {
		returnOp = Opcodes.IRETURN,
	})
	table.union(infoForPrims.byte, {
		returnOp = Opcodes.IRETURN,
	})
	table.union(infoForPrims.short, {
		returnOp = Opcodes.IRETURN,
	})
	table.union(infoForPrims.int, {
		returnOp = Opcodes.IRETURN,
	})
	table.union(infoForPrims.long, {
		returnOp = Opcodes.LRETURN,
	})
	table.union(infoForPrims.float, {
		returnOp = Opcodes.FRETURN,
	})
	table.union(infoForPrims.double, {
		returnOp = Opcodes.DRETURN,
	})
end


-- Where to put the saved closures?
-- I'd put them in the JavaClass object but I'm sure it would go out of scope too quickly
-- So I'll put them here with key = classname
local M = {}
M.savedClosures = {}

--[[
args:
	env = JavaEnv
	name = dot-separated class name
	parent = parent-class, or java.lang.Object by default
	interfaces = list-of-interfaces to use
	fields = {
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
	ctors = {
		{
			func = Lua callback function
			sig =
			isPrivate =
			isPublic =
		},
		...
	}
	methods = {
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

	local NativeCallback = require 'java.tests.nativecallback_asm'(J)
	local NativeCallbackSlashSep = NativeCallback._classpath:gsub('%.', '/')

	local classname = assert.type(assert.index(args, 'name'), 'string')
	if not classname then
		classname = 'io.github.thenumbernine.LuaJavaClass_'
			..bit.tohex(ffi.cast('uint64_t', J._ptr), bit.lshift(ffi.sizeof'intptr_t', 1))
			..'_'..uniqueNameCounter
		uniqueNameCounter = uniqueNameCounter + 1
	end
	local classnameSlashSep = classname:gsub('%.', '/')

	local parentClass = args.parentClass or 'java.lang.Object'
	local parentClassSlashSep = parentClass:gsub('%.', '/')

	local interfaces
	local srcInterfaces = args.interfaces
	if srcInterfaces  then
		local n = #srcInterfaces
		interfaces = J:_newArray(J.String, n)
		for i=0,n-1 do
			interfaces[i] = srcInterfaces[i+1]
		end
	end

	local ClassWriter = J.org.objectweb.asm.ClassWriter
	assert(JavaClass:isa(ClassWriter), "JRE isn't finding ASM")
	local Opcodes = J.org.objectweb.asm.Opcodes

	-- do this once but only after finding ASM
	initInfoForPrims(Opcodes)

	local cw = ClassWriter(ClassWriter.COMPUTE_FRAMES)

	cw:visit(
		Opcodes.V1_6,		-- TODO match with J._vm.version
		Opcodes.ACC_PUBLIC,	-- TODO flags
		classnameSlashSep,
		nil,
		parentClassSlashSep,
		interfaces
	)

	for _,field in ipairs(args.fields or {}) do
		local fieldName = assert.type(assert.index(field, 'name'), 'string')
		local fieldSig = getJNISig((assert.type(assert.index(field, 'sig'), 'string')))
		local fv = cw:visitField(
			Opcodes.ACC_PUBLIC,	-- TODO flags
			fieldName,
			fieldSig,
			nil,
			nil
		)
		fv:visitEnd()
	end

	local closures = table()	-- to-free
	M.savedClosures[classname] =  closures

	local function buildLuaWrapperMethod(method)
		local sig = method.sig or {}
		sig[1] = sig[1] or 'void'
		local returnType = sig[1]
		local mv = cw:visitMethod(
			Opcodes.ACC_PUBLIC,			-- TODO flags
			method.name,
			getJNISig(sig),
			nil,
			nil
		)
		mv:visitCode()

		-- special for ctors, call parent
		if method.name == '<init>' then
			mv:visitVarInsn(Opcodes.ALOAD, 0)
			mv:visitMethodInsn(
				Opcodes.INVOKESPECIAL,
				parentClassSlashSep,
				'<init>',
				'()V',		-- TODO this always calls the parent-class's <init>().  what about dif args?
				false
			)
		end

		local func = assert.index(method, 'func')	-- should I assert it is a function? does LuaJIT function closure casting handle __call of objects automatically?
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

		-- now native callback will get ...
		-- 1) a funcptr from a closure
		mv:visitLdcInsn(
			J.Long(
				ffi.cast('jlong', closure)
			)
		)

		-- 2) an Object[] of {this, ... rest of args of the method}
		local sigNumArgs = #sig-1
print('sigNumArgs', sigNumArgs)
		mv:visitIntInsn(Opcodes.BIPUSH, sigNumArgs+1)		-- +1 for 'this' (TODO static)
		mv:visitTypeInsn(Opcodes.ANEWARRAY, 'java/lang/Object')

		-- set args[0] = this
		mv:visitInsn(Opcodes.DUP)
		mv:visitInsn(Opcodes.ICONST_0)
		mv:visitVarInsn(Opcodes.ALOAD, 0)
		mv:visitInsn(Opcodes.AASTORE)

		if sigNumArgs > 0 then
			local localVarIndex = 1
			for i=0,sigNumArgs-1 do		-- 0-based argument index
				mv:visitInsn(Opcodes.DUP)

				-- write to args[i+1] to skip 'this'
				if i+1 <= 5 then
					mv:visitInsn(Opcodes.ICONST_0+i+1)
				else
					mv:visitIntInsn(Opcodes.BIPUSH, i+1)
				end

				local argSig = sig[i+2]
				local primInfo = infoForPrims[argSig]

				local argOpcode = primInfo and Opcodes.ILOAD or Opcodes.ALOAD
				mv:visitVarInsn(argOpcode, localVarIndex)
				if primInfo then
					local boxedTypeSlashSep = primInfo.boxedType:gsub('%.', '/')
					mv:visitMethodInsn(
						Opcodes.INVOKESTATIC,
						boxedTypeSlashSep,
						'valueOf',
						getJNISig{primInfo.boxedType, primInfo.name},
						false
					)
				end

				mv:visitInsn(Opcodes.AASTORE)

				if argSig == 'long' or argSig == 'double' then
					localVarIndex = localVarIndex + 2
				else
					localVarIndex = localVarIndex + 1
				end
			end
		end

		-- call `NativeCallback.run(funcptr, Object[]{this, args...})`
		mv:visitMethodInsn(
			Opcodes.INVOKESTATIC,
			NativeCallbackSlashSep,
			'run',
			'(JLjava/lang/Object;)Ljava/lang/Object;',
			false
		)

		-- now on the stack is a java.lang.Object from NativeCallback.run()
		-- next, convert it depending on this function's return type
--DEBUG:print('returnType', returnType)
		local primInfo = infoForPrims[returnType]
		if returnType == 'void' then
			mv:visitInsn(Opcodes.RETURN)
		elseif primInfo then
			-- cast to BoxedType
			local boxedTypeSlashName = primInfo.boxedType:gsub('%.', '/')
			mv:visitTypeInsn(
				Opcodes.CHECKCAST,
				boxedTypeSlashName
			)
			mv:visitMethodInsn(
				Opcodes.INVOKEVIRTUAL,
				boxedTypeSlashName,
				primInfo.name..'Value',
				getJNISig{primInfo.name},
				false)
			mv:visitInsn(primInfo.returnOp)
		else
			mv:visitTypeInsn(
				Opcodes.CHECKCAST,
				(returnType:gsub('%.', '/'))
			)
			mv:visitInsn(Opcodes.ARETURN)
		end

		mv:visitMaxs(
			10,	-- max stack
			1 + (table.sub(sig, 2):mapi(function(sigi)
				-- max locals ... wait, locals include args right?
				-- so any sig that is double or long needs 2, otherwise 1?
				return (sigi == 'long' or sigi == 'double') and 2 or 1
			end):sum() or 0)
		)
		mv:visitEnd()
	end

	local srcCtors = args.ctors
	if not srcCtors or #srcCtors == 0 then
		-- provide a default ctor, no need for closure or callback
		local init = cw:visitMethod(Opcodes.ACC_PUBLIC, '<init>', '()V', nil, nil)
		init:visitCode()
		init:visitVarInsn(Opcodes.ALOAD, 0)
		init:visitMethodInsn(Opcodes.INVOKESPECIAL, parentClassSlashSep, '<init>', '()V', false)
		init:visitInsn(Opcodes.RETURN)
		init:visitMaxs(0, 0)
		init:visitEnd()
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

	cw:visitEnd()

	local code = cw:toByteArray()

	-- create the java .class to go along with it
	local classAsObj = require 'java.tests.bytecodetoclass'(J, code, classnameSlashSep)
	local cl = J:_getClassForJClass(classAsObj._ptr)
	return cl
end
return setmetatable(M, {
	__call = M.run,
})
