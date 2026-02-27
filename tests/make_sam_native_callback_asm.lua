--[[
as the name says:
this makes a subclass of a SAM interface (or abstract class)
using Java-ASM
and redirects the contents of the SAM function to io.github.thenumbernine.NativeCallback
--]]
local JavaClass = require 'java.class'

local uniqueNameCounter = 1

local ffi = require 'ffi'
local assert = require 'ext.assert'
local table = require 'ext.table'
local getJNISig = require 'java.util'.getJNISig
local infoForPrims = require 'java.util'.infoForPrims

return function(J, samClass)
	assert(JavaClass:isa(samClass), "expected samClass to be a JavaClass")

	local samMethod = samClass._samMethod
	local samClassSlashSep = samClass._classpath:gsub('%.', '/')

	local parentClassSlashSep = samClass._isInterface
		and 'java/lang/Object'
		or samClassSlashSep

	local interfaces = samClass._isInterface
		and J:_newArray(J.String, 1, J:_str(samClassSlashSep))
		or nil

	local NativeCallback = require 'java.tests.nativecallback_asm'(J)

	local ClassWriter = J.org.objectweb.asm.ClassWriter
	assert(JavaClass:isa(ClassWriter), "JRE isn't finding ASM")
	local cw = ClassWriter(ClassWriter.COMPUTE_FRAMES)

	local Opcodes = J.org.objectweb.asm.Opcodes

	local newClassName = 'io/github/thenumbernine/SAMNativeCallback_'
		..bit.tohex(ffi.cast('uint64_t', J._ptr), bit.lshift(ffi.sizeof'intptr_t', 1))
		..'_'..uniqueNameCounter
--DEBUG:print('newClassName', newClassName)
	uniqueNameCounter = uniqueNameCounter + 1

	--public class ${newClassName} extends java.lang.Object {
	cw:visit(
		Opcodes.V1_6,	-- TODO match with J._vm.version
		Opcodes.ACC_PUBLIC,
		newClassName,
		nil,
		parentClassSlashSep,
		interfaces)

	--	long funcptr;
	cw:visitField(Opcodes.ACC_PUBLIC, 'funcptr', 'J', nil, nil)
		:visitEnd()

	--	public ${newClassName}(long funcptr)
	local init = cw:visitMethod(Opcodes.ACC_PUBLIC, '<init>', '(J)V', nil, nil)
	init:visitCode()
	init:visitVarInsn(Opcodes.ALOAD, 0)
	init:visitMethodInsn(Opcodes.INVOKESPECIAL, parentClassSlashSep, '<init>', '()V', false)
	init:visitVarInsn(Opcodes.ALOAD, 0)
	init:visitVarInsn(Opcodes.LLOAD, 1)
	init:visitFieldInsn(Opcodes.PUTFIELD, newClassName, 'funcptr', 'J')
	init:visitInsn(Opcodes.RETURN)
	init:visitMaxs(0, 0)
	init:visitEnd()

	-- write our wrapping function
	-- can this work with Java varargs?
	local mv = cw:visitMethod(
		Opcodes.ACC_PUBLIC,
		assert.type(samMethod._name, 'string'),
		getJNISig(samMethod._sig),
		nil,
		nil
	)
	mv:visitCode()

	--		push 'this.funcptr'
	mv:visitVarInsn(Opcodes.ALOAD, 0);
	mv:visitFieldInsn(Opcodes.GETFIELD, newClassName, 'funcptr', 'J')

	local sigNumArgs = #samMethod._sig-1
	if sigNumArgs == 0 then
		mv:visitInsn(Opcodes.ACONST_NULL)
	else
		mv:visitIntInsn(Opcodes.BIPUSH, sigNumArgs)
		mv:visitTypeInsn(Opcodes.ANEWARRAY, 'java/lang/Object')

		local localVarIndex = 1
		for i=0,sigNumArgs-1 do
			mv:visitInsn(Opcodes.DUP)

			if i <= 5 then
				mv:visitInsn(Opcodes.ICONST_0+i)
			else
				mv:visitIntInsn(Opcodes.BIPUSH, i)
			end

			local argSig = samMethod._sig[i+2]
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
	--		call 'NativeCallback.run'
	mv:visitMethodInsn(
		Opcodes.INVOKESTATIC,
		NativeCallback._classpath:gsub('%.', '/'),
		assert(NativeCallback._runMethodName),
		'(JLjava/lang/Object;)Ljava/lang/Object;',
		false
	)

		-- TODO TODO return any result

	mv:visitInsn(Opcodes.RETURN)
	mv:visitMaxs(
		10,	-- max stack
		1 + (table.sub(samMethod._sig, 2):mapi(function(sigi)
			-- max locals ... wait, locals include args right?
			-- so any sig that is double or long needs 2, otherwise 1?
			return (sigi == 'long' or sigi == 'double') and 2 or 1
		end):sum() or 0)
	)
	mv:visitEnd()

	--}
	cw:visitEnd()

	local code = cw:toByteArray()

	-- create the java .class to go along with it
	local classAsObj = require 'java.tests.bytecodetoclass'(J, code, newClassName)

	local cl = J:_getClassForJClass(classAsObj._ptr)
	-- 'cl' is a JavaClass instance
	cl._cb = function(self, callback)
		assert.type(callback, 'function')

		-- arg = nil or a jobject to Object[]
		local unpackCallback = function(arg)
			if arg ~= nil then
				arg = J:_javaToLuaArg(arg, 'java.lang.Object[]')
				return callback(arg:_unpack())
			else
				return callback()
			end
		end

		local closure = ffi.cast('void *(*)(void*)', unpackCallback)
		local obj = self:_new(
			ffi.cast('jlong', closure)
		)

		rawset(obj, '_callbackDontGC', unpackCallback)
		rawset(obj, '_callbackClosure', closure)

		-- TODO override obj __gc to free closure
		local mt = getmetatable(obj)
		-- assert each object gets their own mt ...
		assert.ne(mt, cl)
		local oldgc = mt.__gc
		mt.__gc = function(self)
			local closure = rawget(self, '_callbackClosure')
			if closure then closure:free() end
			rawset(self, '_callbackClosure', nil)
			rawset(self, '_callbackDontGC', nil)
			if oldgc then oldgc(self) end
		end

		return obj
	end

	-- override ctor to accept function
	-- TODO put this in JavaClass:_new, but that will make everything dependent on ASM...
	local oldnew = cl._new	-- should be JavaClass._new
	cl._new = function(self, ...)
		local arg = ...
		if type(arg) == 'function' then
			return self:_cb(arg)
		else
			return oldnew(self, ...)
		end
	end
	return cl
end
