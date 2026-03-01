-- NativeActionListener using JavaClassData
-- TODO just use SAM? or at least use java.luacass ... much more concise
local path = require 'ext.path'
local JavaClassData = require 'java.classdata'
return function(J)
	local NativeCallback = require 'java.nativecallback'(J)

	local newClassName = 'io.github.thenumbernine.NativeActionListener'
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
		interfaces = {'java/awt/event/ActionListener'},
		fields = {
			{
				isPublic = true,
				name = 'funcptr',
				sig = 'J',
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
				name='actionPerformed',
				sig='(Ljava/awt/event/ActionEvent;)V',
				maxLocals=2,
				maxStack=3,
				code = [[
aload_0
getfield ]]..newClassNameSlashSep..[[ funcptr J
aload_1
invokestatic ]]..NativeCallback._classpath:gsub('%.', '/')
	..' '..assert(NativeCallback._runMethodName)
	..[[ (JLjava/lang/Object;)Ljava/lang/Object;
pop
return
]],				
			}
		},
	}

	local code = cw:compile()
	local classAsObj = require 'java.tests.bytecodetoclass'(J, code, newClassName)
	local cl = J:_getClassForJClass(classAsObj._ptr)
	return cl
end
