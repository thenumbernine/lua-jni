--[[
nativecallback but using JavaClassData instead of Java-ASM
--]]
local JavaClassData = require 'java.clasdata'
return function(J)
	-- need to build the jni .c side
	require 'java.build'.C{
		src = 'io_github_thenumbernine_NativeCallback.c',
		dst = 'libio_github_thenumbernine_NativeCallback.so',
	}

	local newClassName = 'io.github.thenumbernine.NativeCallback'
	local newClassNameSlashSep = newClassName:gsub('%.', '/')

	-- check if it's already loaded
	local cl = J:_findClass(newClassName)
	if cl then return cl end

	local runMethodName = 'run'

	local cw = JavaClassData{
		version = 0x4100,	-- major in high byte, minor in low byte ...
		isPublic = true,
		thisClass = newClassNameSlashSep,
		isSuper = true,	-- "Treat superclass methods specially when invoked by the invokespecial instruction."
		superClass = 'java/lang/Object',
		methods = {
			{
				isStatic = true,
				name = '<clinit>',
				sig = '()V',
				code = {
					{'ldc', (path:cwd()/'libio_github_thenumbernine_NativeCallback.so').path},
					{'invokestatic', 'java/lang/System', 'load','(Ljava/lang/String;)V'},
					{'return'},
				},
			},
			{
				isNative = true,
				isPublic = true,
				isStatic = true,
				name = runMethodName,
				sig = '(JLjava/lang/Object;)Ljava/lang/Object;',
			},
		},
	}

	local code = cw:compile()
	local classAsObj = require 'java.tests.bytecodetoclass'(J, code, newClassName)
	local cl = J:_getClassForJClass(classAsObj._ptr)
	rawset(cl, '_runMethodName', runMethodName)
	return cl
end
