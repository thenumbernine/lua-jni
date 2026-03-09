-- NativeActionListener using JavaASMClass
-- TODO just use SAM? or at least use java.luacass ... much more concise
local path = require 'ext.path'
local JavaASMClass = require 'java.asmclass'
return function(J)
	local NativeCallback = require 'java.nativecallback'(J)

	local newClassName = 'io.github.thenumbernine.NativeActionListener'

	-- check if it's already loaded
	local cl = J:_findClass(newClassName)
	if cl then return cl end

	local cw = JavaASMClass{
		version = 0x41,
		isPublic = true,
		isSuper = true,
		thisClass = newClassName,
		superClass = 'java.lang.Object',
		interfaces = {'java.awt.event.ActionListener'},
		fields = {
			{
				isPublic = true,
				name = 'funcptr',
				sig = 'long',
			},
		},
		methods={
			{
				isPublic = true,
				name = '<init>',
				sig = {'void', 'long'},
				maxStack = 3,
				maxLocals = 3,
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
				isPublic = true,
				name = 'actionPerformed',
				sig = {'void', 'java.awt.event.ActionEvent'},
				maxStack = 3,
				maxLocals = 2,
				code = [[
aload_0
getfield ]]..newClassName..[[ funcptr J
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
	local cl = J:_fromJClass(classAsObj._ptr)
	return cl
end
