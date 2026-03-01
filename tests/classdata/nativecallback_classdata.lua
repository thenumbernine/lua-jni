-- nativecallback but using JavaClassData
local path = require 'ext.path'
local JavaClassData = require 'java.classdata'
return function(J)
	-- need to build the jni .c side
	require 'java.build'.C{
		src = 'io_github_thenumbernine_NativeCallback.c',
		dst = 'libio_github_thenumbernine_NativeCallback.so',
	}

	local newClassName = 'io.github.thenumbernine.NativeCallback'
	local newClassNameSlashSep = newClassName:gsub('%.', '/')

	local runMethodName = 'run'

	-- check if it's already loaded
	local cl = J:_findClass(newClassName)
	if cl then
		rawset(cl, '_runMethodName', runMethodName)
		return cl
	end

	local cw = JavaClassData{
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
					{'ldc', 'string', (path:cwd()/'libio_github_thenumbernine_NativeCallback.so').path},
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

	local code = cw:compile()
	local classAsObj = require 'java.tests.bytecodetoclass'(J, code, newClassName)
	local cl = J:_getClassForJClass(classAsObj._ptr)
	rawset(cl, '_runMethodName', runMethodName)
	return cl
end
