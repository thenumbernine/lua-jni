-- nativerunnable uut using JavaASMClass
local path = require 'ext.path'
local JavaASMClass = require 'java.asmclass'
return function(J)
	local NativeCallback = require 'java.tests.asmclass.nativecallback_asmclass'(J)

	local newClassName = 'io.github.thenumbernine.NativeRunnable'

	-- check if it's already loaded
	local cl = J:_findClass(newClassName)
	if cl then return cl end

	local cw = JavaASMClass{
		version = 0x41,
		isPublic = true,
		isSuper = true,
		thisClass = newClassName,
		superClass = 'java.lang.Object',
		interfaces = {'java.lang.Runnable'},
		fields = {
			{
				isPublic = true,
				name = 'funcptr',
				sig = 'long',
			},
			{
				isPublic = true,
				name = 'arg',
				sig = 'java.lang.Object',
			},
		},
		methods={
			{
				isPublic=true,
				name='<init>',
				sig = {'void', 'long'},
				maxStack=3,
				maxLocals=3,
				code = [[
aload_0
invokespecial java.lang.Object <init> ()V
aload_0
lload_1
putfield ]]..newClassName..[[ funcptr J
return
]],
			},
			{
				isPublic=true,
				name='<init>',
				sig = {'void', 'long', 'java.lang.Object'},
				maxStack=3,
				maxLocals=4,
				code = [[
aload_0
invokespecial java.lang.Object <init> ()V
aload_0
lload_1
putfield ]]..newClassName..[[ funcptr J
aload_0
aload_3
putfield ]]..newClassName..[[ arg Ljava/lang/Object;
return
]],
			},
			{
				isPublic=true,
				name='run',
				sig = {'void'},
				maxStack=3,
				maxLocals=1,
				code = [[
aload_0
getfield ]]..newClassName..[[ funcptr J
aload_0
getfield ]]..newClassName..[[ arg Ljava/lang/Object;
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
	local cl = J:_fromJClass(classAsObj._ptr)
	return cl
end

