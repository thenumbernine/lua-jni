-- NativeActionListener using JavaClassData
local path = require 'ext.path'
local JavaClassData = require 'java.classdata'
return function(J)
	local NativeCallback = require 'java.tests.classdata.nativecallback_classdata'(J)

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
				code={
					{'aload_0'},
					{'invokespecial', 'java/lang/Object', '<init>', '()V'},
					{'aload_0'},
					{'lload_1'},
					{'putfield', newClassNameSlashSep, 'funcptr', 'J'},
					{'return'},
				},
				maxLocals=3,
				maxStack=3,
			},
			{
				isPublic=true,
				name='actionPerformed',
				sig='(Ljava/awt/event/ActionEvent;)V',
				code={
					{'aload_0'},
					{'getfield', newClassNameSlashSep, 'funcptr', 'J'},
					{'aload_1'},
					{'invokestatic',
						NativeCallback._classpath:gsub('%.', '/'),
						assert(NativeCallback._runMethodName),
						'(JLjava/lang/Object;)Ljava/lang/Object;'},
					{'pop'},
					{'return'},
				},
				maxLocals=2,
				maxStack=3,
			}
		},
	}

	local code = cw:compile()
	local classAsObj = require 'java.tests.bytecodetoclass'(J, code, newClassName)
	local cl = J:_getClassForJClass(classAsObj._ptr)
	return cl
end


