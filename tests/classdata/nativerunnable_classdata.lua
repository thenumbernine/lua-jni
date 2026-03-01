-- nativerunnable uut using JavaClassData
local path = require 'ext.path'
local JavaClassData = require 'java.classdata'
return function(J)
	local NativeCallback = require 'java.nativecallback'(J)

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
				isPublic=true,
				name='<init>',
				sig='(J)V',
				code={
					{'aload_0'},
					{'invokespecial', 'java/lang/Object', '<init>', '()V'},
					{'aload_0'},
					{'lload_1'},
					{'putfield', newClassNameSlashSep, 'funcptr', 'J'},
					{'return'},
				},
				--[[
				lineNos={
					{lineNo=7, startPC=0},
					{lineNo=8, startPC=4},
					{lineNo=9, startPC=9},
				},
				--]]
				maxLocals=3,
				maxStack=3,
			},
			{
				isPublic=true,
				name='<init>',
				sig='(JLjava/lang/Object;)V',
				code={
					{'aload_0'},
					{'invokespecial', 'java/lang/Object', '<init>', '()V'},
					{'aload_0'},
					{'lload_1'},
					{'putfield', newClassNameSlashSep, 'funcptr', 'J'},
					{'aload_0'},
					{'aload_3'},
					{'putfield', newClassNameSlashSep, 'arg', 'Ljava/lang/Object;'},
					{'return'},
				},
				--[[
				lineNos={
					{lineNo=11, startPC=0},
					{lineNo=12, startPC=4},
					{lineNo=13, startPC=9},
					{lineNo=14, startPC=14},
				},
				--]]
				maxLocals=4,
				maxStack=3,
			},
			{
				isPublic=true,
				name='run',
				sig='()V',
				code={
					{'aload_0'},
					{'getfield', newClassNameSlashSep, 'funcptr', 'J'},
					{'aload_0'},
					{'getfield', newClassNameSlashSep, 'arg', 'Ljava/lang/Object;'},
					{'invokestatic',
						NativeCallback._classpath:gsub('%.', '/'),
						assert(NativeCallback._runMethodName),
						'(JLjava/lang/Object;)Ljava/lang/Object;'},
					{'pop'},
					{'return'},
				},
				--[[
				lineNos={
					{lineNo=18, startPC=0},
					{lineNo=19, startPC=12},
				},
				--]]
				maxLocals=1,
				maxStack=3,
			}
		},
	}

	local code = cw:compile()
	local classAsObj = require 'java.tests.bytecodetoclass'(J, code, newClassName)
	local cl = J:_getClassForJClass(classAsObj._ptr)
	return cl
end

