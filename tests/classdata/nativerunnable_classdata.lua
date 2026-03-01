--[[
nativerunnable uut using JavaClassData instead of Java-ASM
--]]
local path = require 'ext.path'
local JavaClassData = require 'java.classdata'
return function(J)
	local NativeCallback = require 'java.tests.classdata.nativecallback_classdata'(J)

	local newClassName = 'io.github.thenumbernine.NativeRunnable'
	local newClassNameSlashSep = newClassName:gsub('%.', '/')

	-- check if it's already loaded
	local cl = J:_findClass(newClassName)
	if cl then return cl end

	local cw = JavaClassData{
		version = 0x41,
		isPublic = true,
		isSuper = true,
		thisClass = newClassNameSlashSep,
		superClass = 'java/lang/Object',
		interfaces = {'java/lang/Runnable'},
		fields = {
			{
				isPublic = true,
				name = 'funcptr',
				sig = 'J',
			},
			{
				isPublic = true,
				name = 'arg',
				sig = 'Ljava/lang/Object;',
			},
		},
		methods={
			{
				code={
					{'aload_0'},
					{'invokespecial', 'java/lang/Object', '<init>', '()V'},
					{'aload_0'},
					{'lload_1'},
					{'putfield', 'io/github/thenumbernine/NativeRunnable', 'funcptr', 'J'},
					{'return'}
				},
				isPublic=true,
				lineNos={
					{lineNo=7, startPC=0},
					{lineNo=8, startPC=4},
					{lineNo=9, startPC=9}
				},
				maxLocals=3,
				maxStack=3,
				name='<init>',
				sig='(J)V'
			},
			{
				code={
					{'aload_0'},
					{'invokespecial', 'java/lang/Object', '<init>', '()V'},
					{'aload_0'},
					{'lload_1'},
					{'putfield', 'io/github/thenumbernine/NativeRunnable', 'funcptr', 'J'},
					{'aload_0'},
					{'aload_3'},
					{'putfield', 'io/github/thenumbernine/NativeRunnable', 'arg', 'Ljava/lang/Object;'},
					{'return'}
				},
				isPublic=true,
				lineNos={
					{lineNo=11, startPC=0},
					{lineNo=12, startPC=4},
					{lineNo=13, startPC=9},
					{lineNo=14, startPC=14}
				},
				maxLocals=4,
				maxStack=3,
				name='<init>',
				sig='(JLjava/lang/Object;)V'
			},
			{
				code={
					{'aload_0'},
					{'getfield', 'io/github/thenumbernine/NativeRunnable', 'funcptr', 'J'},
					{'aload_0'},
					{'getfield', 'io/github/thenumbernine/NativeRunnable', 'arg', 'Ljava/lang/Object;'},
					{'invokestatic', 
						NativeCallback._classpath:gsub('%.', '/'),
						assert(NativeCallback._runMethodName),
						'(JLjava/lang/Object;)Ljava/lang/Object;'},
					{'pop'},
					{'return'}
				},
				isPublic=true,
				lineNos={
					{lineNo=18, startPC=0},
					{lineNo=19, startPC=12}
				},
				maxLocals=1,
				maxStack=3,
				name='run',
				sig='()V'
			}
		},
	}

	local code = cw:compile()
	local classAsObj = require 'java.tests.bytecodetoclass'(J, code, newClassName)
	local cl = J:_getClassForJClass(classAsObj._ptr)
	return cl
end

