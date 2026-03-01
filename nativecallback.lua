--[[
io.github.thenumbernine.NativeCallback class but implemented with JavaClassData

This still requires the libio_github_thenumbernine_NativeCallback.so file to be present
--]]
local path = require 'ext.path'
local JavaClassData = require 'java.classdata'

local M = {}

-- find where we are, assume libio_github_thenumbernine_NativeCallback.so is also there
-- change it later if you can't build in this dir
M.srcDir = path(package.searchpath('java.nativecallback', package.path)):getdir()

function M:run(J)
	local newClassName = 'io.github.thenumbernine.NativeCallback'
	local newClassNameSlashSep = newClassName:gsub('%.', '/')

	local runMethodName = 'run'

	-- check if it's already loaded
	local cl = J:_findClass(newClassName)
	if cl then
		rawset(cl, '_runMethodName', runMethodName)
		return cl
	end

	-- still need to build the jni .c side
	local srcFp = self.srcDir/'io_github_thenumbernine_NativeCallback.c'
	local soFp = self.srcDir/'libio_github_thenumbernine_NativeCallback.so'
	require 'java.build'.C{
		src = srcFp.path,
		dst = soFp.path,
	}

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
				code = {
					{'aload_0'},
					{'invokespecial', 'java/lang/Object', '<init>', '()V'},
					{'return'}
				},
				maxLocals = 1,
				maxStack = 1,
				--[[ necessary?
				lineNos={
					{lineNo=3, startPC=0}
				},
				--]]
			},
			{
				isNative = true,
				isPublic = true,
				isStatic = true,
				name = runMethodName,
				sig = '(JLjava/lang/Object;)Ljava/lang/Object;',
			},
			{
				isStatic = true,
				name = '<clinit>',
				sig = '()V',
				code = {
					{'ldc', 'string', soFp.path},
					{'invokestatic', 'java/lang/System', 'load','(Ljava/lang/String;)V'},
					{'return'},
				},
				maxLocals = 0,
				maxStack = 1,
				--[[ necessary?
				lineNos={
					{lineNo=5, startPC=0},
					{lineNo=6, startPC=5}
				},
				--]]
			},
		},
	}

	local cl = J:_defineClass(classData)
	rawset(cl, '_runMethodName', runMethodName)
	return cl
end

return setmetatable(M, {
	__call = M.run,
})
