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

-- Where to put the saved closures?
-- I'd put them in the JavaClass object but I'm sure it would go out of scope too quickly
-- So I'll put them here with key = classname
local savedClosures = {}

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
return function(args)
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
	local cw = ClassWriter(ClassWriter.COMPUTE_FRAMES)
	
	local Opcodes = J.org.objectweb.asm.Opcodes

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
	savedClosures[classname] =  closures

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
		local wrapper = function(this, arg)
			this = J:_javaToLuaArg(this, classname)
			arg = J:_javaToLuaArg(arg, 'java.lang.Object[]')
			local result
			if arg ~= nil then
				arg = J:_javaToLuaArg(arg, 'java.lang.Object[]')
				result = func(arg:_unpack())
			else
				result = func()
			end
			if returnType ~= 'void' then
				return J:_luaToJavaArg(result, returnType)
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
		if sigNumArgs == 0 then
			mv:visitInsn(Opcodes.ACONST_NULL)
		else
			mv:visitIntInsn(Opcodes.BIPUSH, sigNumArgs+1)		-- +1 for 'this' (TODO static)
			mv:visitTypeInsn(Opcodes.ANEWARRAY, 'java/lang/Object')
			
			-- set args[0] = this
			mv:visitInsn(Opcodes.DUP)
			mv:visitInsn(Opcodes.ICONST_0)
			mv:visitVarInsn(Opcodes.ALOAD, 0)
			mv:visitInsn(Opcodes.AASTORE)

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

		-- return any result
		if returnType == 'void' then
			mv:visitInsn(Opcodes.RETURN)
		elseif returnType == 'long' then
			mv:visitInsn(Opcodes.LRETURN)
		elseif returnType == 'float' then
			mv:visitInsn(Opcodes.FRETURN)
		elseif returnType == 'double' then
			mv:visitInsn(Opcodes.DRETURN)
		elseif not infoForPrims[returnType] then
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
		-- provide a default ctor
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
