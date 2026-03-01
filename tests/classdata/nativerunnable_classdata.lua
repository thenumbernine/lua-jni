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
				maxLocals=3,
				maxStack=3,
				code = [[
aload_0
invokespecial java/lang/Object <init> ()V
aload_0
lload_1
putfield ]]..newClassNameSlashSep..[[ funcptr J
return
]],
			},
			{
				isPublic=true,
				name='<init>',
				sig='(JLjava/lang/Object;)V',
				maxLocals=4,
				maxStack=3,
				code = [[
aload_0
invokespecial java/lang/Object <init> ()V
aload_0
lload_1
putfield ]]..newClassNameSlashSep..[[ funcptr J
aload_0
aload_3
putfield ]]..newClassNameSlashSep..[[ arg Ljava/lang/Object;
return
]],
			},
			{
				isPublic=true,
				name='run',
				sig='()V',
				maxLocals=1,
				maxStack=3,
				code = [[
aload_0
getfield ]]..newClassNameSlashSep..[[ funcptr J
aload_0
getfield ]]..newClassNameSlashSep..[[ arg Ljava/lang/Object;
invokestatic ]]..NativeCallback._classpath:gsub('%.', '/')
..' '..assert(NativeCallback._runMethodName)
..[[ (JLjava/lang/Object;)Ljava/lang/Object;
pop
return
]],
			},
		},
	}

	local classByteCode = cw:compile()
	local classAsObj = require 'java.tests.bytecodetoclass'(J, classByteCode, newClassName)
	local cl = J:_getClassForJClass(classAsObj._ptr)
	return cl
end

