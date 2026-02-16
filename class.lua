local class = require 'ext.class'
local assert = require 'ext.assert'
local string = require 'ext.string'
local table = require 'ext.table'
local JavaMethod = require 'java.method'

--[[
getJNISig accepts string for a single arg
	or a table for a method
	where the first element of hte table is the return type
	and the rest is the method call argumetns
TODO this won't handle an array-of-methods
I 
--]]
local getJNISig
local function getJNISigArg(s)
	if type(s) == 'table' then return getJNISig(s) end
	local arrayCount = 0
	while true do
		local rest = s:match'^(.*)%[%]$'
		if not rest then break end
		arrayCount = arrayCount + 1
		s = rest
	end
	return ('['):rep(arrayCount)
	.. (
		({
			boolean = 'Z',
			byte = 'B',
			char = 'C',	-- in java, char is 16bit
			short = 'S',
			int = 'I',
			long = 'J',
			float = 'F',
			double = 'D',
			void = 'V',
		})[s] 
		or 'L'..s:gsub('%.', '/')..';'
	)
end
local function getJNISig(sig)
	return '('
		..table.sub(sig, 2)
			:mapi(getJNISigArg)
			:concat()
	..')'..getJNISigArg(sig[1] or 'void')
end


local JavaClass = class()
JavaClass.__name = 'JavaClass'

function JavaClass:init(args)
	self.env = assert.index(args, 'env')
	self.ptr = assert.index(args, 'ptr')
end

--[[
args:
	name
	sig
		= table of args as slash-separated classpaths, 
		first arg is return type
	static = boolean
--]]
function JavaClass:getMethod(args)
	assert.type(args, 'table')
	local funcname = assert.type(assert.index(args, 'name'), 'string')
	local static = args.static
	local sig = assert.type(assert.index(args, 'sig'), 'table')
	local sigstr = getJNISig(sig)
--DEBUG:print('sigstr', sigstr)

	local method 
	if static then
		method = self.env.ptr[0].GetStaticMethodID(self.env.ptr, self.ptr, funcname, sigstr)
	else
		method = self.env.ptr[0].GetMethodID(self.env.ptr, self.ptr, funcname, sigstr)
	end
	if method == nil then
		error("failed to find "..tostring(funcname)..' '..tostring(sigstr))
	end
	return JavaMethod{
		env = self.env,
		class = self,
		ptr = method,
		sig = sig,
		static = static,
	}
end

function JavaClass:getName()
	-- store this for safe keeping
	-- TODO maybe a java.classesloaded[] table or something
	JavaClass.java_lang_Class = JavaClass.java_lang_Class 
		or self.env:findClass'java/lang/Class'
	
	JavaClass.java_lang_Class_getName = JavaClass.java_lang_Class_getName
		or JavaClass.java_lang_Class:getMethod{name='getName', sig={'java.lang.String'}}

	return JavaClass.java_lang_Class_getName(self)
end

function JavaClass:__tostring()
	return self.__name..'('..tostring(self.ptr)..')'
end

JavaClass.__concat = string.concat

return JavaClass
