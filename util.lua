require 'java.ffi.jni'	-- primitive defs
local ffi = require 'ffi'
local table = require 'ext.table'
local assert = require 'ext.assert'

local function deepCopy(t)
	if type(t) ~= 'table' then return t end
	local t2 = table(t)
	for k,v in pairs(t) do
		t2[k] = deepCopy(v)
	end
	return t2
end


--[[
Ok I gotta think of some way to describe the different names ...
There's slash-separated names.  .class files use these.
... arrays are [ prefix, primitives are single-letter.
There's L-slash-separated-semicolon names.  JNI-call-signatures use these, and .dex files use these.
... arrays are [ prefix, primitives are single-letter.
There's dot-separated names.  The Java language API uses these.
... arrays are [] suffix,primitives are whole words.
--]]
local function toSlashSepName(s)
	s = s:match'^L(.*);$' or s	-- from L-slash-sep-; to slash-sep
	s = s:gsub('%.', '/')		-- from dot-sep to slash-sep
	return s
end
local function toDotSepName(s)
	s = s:match'^L(.*);$' or s	-- from L-slash-sep-; to slash-sep
	s = s:gsub('/', '.')		-- from slash-sep to dot-sep
	return s
end
local function toLSlashSepSemName(s)
	s = s:gsub('%.', '/')		-- from dot-sep to slash-sep
	if not s:match'^L.*$' then
		s = 'L'..s..';'			-- from slash-sep to L-slash-sep-;
	end
	return s
end


-- seems this goes somewhere with the sig stuff in java.class
local prims = table{
	'boolean',
	'byte',
	'char',
	'short',
	'int',
	'long',
	'float',
	'double',
}

local boxedTypesForPrims = {
	boolean = 'java.lang.Boolean',
	char = 'java.lang.Char',
	byte = 'java.lang.Byte',
	short = 'java.lang.Short',
	int = 'java.lang.Integer',
	long = 'java.lang.Long',
	float = 'java.lang.Float',
	double = 'java.lang.Double',
}

local infoForPrims = prims:mapi(function(name)
	local info = {}
	info.name = name
	info.boxedType = boxedTypesForPrims[name]
	info.ctype = ffi.typeof('j'..name)
	info.array1Type = ffi.typeof('$[1]', info.ctype)
	info.ptrType = ffi.typeof('$*', info.ctype)
	return info, name
end):setmetatable(nil)


table.union(infoForPrims.boolean, {
	asmClassReturnOp = 'ireturn',
	asmClassLoadOp = 'iload',
	argSize = 1,
})
table.union(infoForPrims.char, {
	asmClassReturnOp = 'ireturn',
	asmClassLoadOp = 'iload',
	argSize = 1,
})
table.union(infoForPrims.byte, {
	asmClassReturnOp = 'ireturn',
	asmClassLoadOp = 'iload',
	argSize = 1,
})
table.union(infoForPrims.short, {
	asmClassReturnOp = 'ireturn',
	asmClassLoadOp = 'iload',
	argSize = 1,
})
table.union(infoForPrims.int, {
	asmClassReturnOp = 'ireturn',
	asmClassLoadOp = 'iload',
	argSize = 1,
})
table.union(infoForPrims.long, {
	asmClassReturnOp = 'lreturn',
	asmClassLoadOp = 'lload',
	argSize = 2,
})
table.union(infoForPrims.float, {
	asmClassReturnOp = 'freturn',
	asmClassLoadOp = 'fload',
	argSize = 1,
})
table.union(infoForPrims.double, {
	asmClassReturnOp = 'dreturn',
	asmClassLoadOp = 'dload',
	argSize = 2,
})




local primSigStrForName = {
	boolean = 'Z',
	byte = 'B',
	char = 'C',	-- in java, char is 16bit
	short = 'S',
	int = 'I',
	long = 'J',
	float = 'F',
	double = 'D',
	void = 'V',
}

local primNameForSigStr = {}
for _,name in ipairs(prims) do
	primNameForSigStr[primSigStrForName[name]] = name
end

--[[
getJNISig accepts string for a single arg
	or a table for a method
	where the first element of hte table is the return type
	and the rest is the method call argumetns
TODO this won't handle an array-of-methods
--]]
local getJNISigMethod
local function getJNISig(s)
	if type(s) == 'table' then
		return getJNISigMethod(s)
	end
	local arrayCount = 0
	while true do
		local rest = s:match'^(.*)%[%]$'
		if not rest then break end
		arrayCount = arrayCount + 1
		s = rest
	end
	return ('['):rep(arrayCount)
	.. (
		primSigStrForName[s]
		or 'L'..s:gsub('%.', '/')..';'	-- convert from .-separator to /-separator
	)
end
function getJNISigMethod(sig)
	return '('
		..table.sub(sig, 2)
			:mapi(getJNISig)
			:concat()
	..')'..getJNISig(sig[1] or 'void')
end

-- takes a JNI style signature for a method, "(" first, return last
-- returns it as a table with the return-type first
local function splitMethodJNISig(str)
	local sig = table()
	local index = 1

	assert.eq(str:sub(index,index), '(')
	index = index + 1

	while str:sub(index, index) ~= ')' do
		assert.le(index, #str)
		local indexStart = index

		while str:sub(index, index) == '[' do
			index = index + 1
		end

		local prim = primNameForSigStr[str:sub(index, index)]
		if prim then
			sig:insert(str:sub(indexStart, index))
			index = index + 1
		else
			assert.eq(str:sub(index, index), 'L')
			index = assert(str:find(';', index, true), "got improper class name")

			sig:insert(str:sub(indexStart, index))
			index = index + 1
		end
	end
	index = index + 1
	assert.le(index, #str)
	sig:insert(1, (str:sub(index)))
	return sig
end

-- accepts a signature string and an index to start reading
-- returns the most recent read type and the next index
-- or nil upon error
local function sigStrToObjSingle(str, index)
--DEBUG:print('sigStrToObj', str)
	local arraySuffix = ''
	while true do
		if str:sub(index, index) ~= '[' then break end
		arraySuffix = arraySuffix .. '[]'
		index = index + 1
	end
--DEBUG:print('arrays', arraySuffix, 'base', str)

	local prim = primNameForSigStr[str:sub(index, index)]
	if prim then
--DEBUG:print'is prim'
		-- TOOD match and return the rest
		return prim..arraySuffix, index + 1
	end
--DEBUG:print('should be class', str)
	if str:sub(index, index) ~= 'L' then
		return nil	--error("sigStrToObj "..tostring(str))
	end

	-- what's left? objects?
	local classpath = str:sub(index):match'^L([^;]*);'
--DEBUG:print('classpath', classpath)
	if not classpath then
		return nil	--error("sigStrToObj "..tostring(str))
	end
	index = index + #classpath + 2	-- +1 for L, +1 for ;
	-- convert from /-separator when it is to .-separator
	classpath = classpath:gsub('/', '%.')
--DEBUG:print('returning', 	classpath..arraySuffix)
	return classpath..arraySuffix, index
end

-- opposite of getJNISig
-- TODO TODO TODO if it's a method then run splitMethodJNISig() on it then convert members individually
local function sigStrToObj(str)
	str = tostring(str)
	if str:sub(1,1) == '(' then
		local sig = table()
		local index = 2
		while str:sub(index,index) ~= ')' do
			local result, resultIndex = sigStrToObjSingle(str, index)
			if not result then
				if not result then
					error("sigStrToObj on function string "..str.." starting at index "..index.." failed to parse arg")
					return
				end
			end
			sig:insert(result)
			index = resultIndex
		end
		index = index + 1	-- skip ')'
		-- read return type last
		if str:sub(index,index) == 'V' then	-- the only place 'void' can be ...
			sig:insert(1, 'void')
			index = index + 1	-- not that it matters
		else
			local result, resultIndex = sigStrToObjSingle(str, index)
			if not result then
				error("sigStrToObj on function string "..str.." starting at index "..index.." failed to parse return type")
			end
			if resultIndex ~= #str+1 then
				error("DANGER sigStrToObj on a function string "..str.." starting at index "..index.." and you got back an index not at the end "..resultIndex)
			end
			sig:insert(1, result)
		end
		return sig
	end

	local result, resultIndex = sigStrToObjSingle(str, 1)
	if not result then return end
	if resultIndex ~= #str+1 then
		error("DANGER sigStrToObj on a single string "..str.." and you got back an index not at the end "..resultIndex)
	end
	return result
end

-- general access flags
-- not used, just a merge of the others
-- each specific (class, fields, methods) access flags is a specialization / subset of this
local accessFlags = {
	isPublic = 0x0001,
	isPrivate = 0x0002,
	isProtected = 0x0004,
	isStatic = 0x0008,
	isFinal = 0x0010,
	isSuperOrSynchronized = 0x0020,	-- 'isSuper' for class, 'isSynchronzied' for method
	isVolatileOrBridge = 0x0040,	-- 'isVolatile' for field, 'isBridge' for method
	isTransientOrVarArgs = 0x0080,	-- 'isTransient' for field, 'isVarArgs' for method
	isNative = 0x0100,
	isInterface = 0x0200,
	isAbstract = 0x0400,
	isStrict = 0x0800,
	isSynthetic = 0x1000,
	isAnnotation = 0x2000,
	isEnum = 0x4000,
	isModule = 0x8000,					-- dalvik: "unused"
	isConstructor = 0x10000,			-- dalvik-only
	isDeclaredSynchronized = 0x20000,	-- dalvik-only
}

-- .class primary-class access flags
-- maybe I don't need this, and just use nestedClassAccessFlags?
local primaryClassAccessFlags = {
	isPublic = 0x0001,
	isFinal = 0x0010,
	isSuper = 0x0020,					-- not in dalvik. 'isSuper' for class, 'isSynchronzied' for method
	isInterface = 0x0200,
	isAbstract = 0x0400,
	isSynthetic = 0x1000,
	isAnnotation = 0x2000,
	isEnum = 0x4000,
	isModule = 0x8000,					-- dalvik: "unused"
}

-- .class nested-class access flags
local nestedClassAccessFlags = {
	isPublic = 0x0001,
	isPrivate = 0x0002,
	isProtected = 0x0004,
	isStatic = 0x0008,
	isFinal = 0x0010,
	isInterface = 0x0200,
	isAbstract = 0x0400,
	isSynthetic = 0x1000,
	isAnnotation = 0x2000,
	isEnum = 0x4000,
}

-- both primary and nested class access flags combined
local classAccessFlags = {
	isPublic = 0x0001,
	isPrivate = 0x0002,
	isProtected = 0x0004,
	isStatic = 0x0008,
	isFinal = 0x0010,
	isSuper = 0x0020,					-- not in dalvik. 'isSuper' for class, 'isSynchronzied' for method
	isInterface = 0x0200,
	isAbstract = 0x0400,
	isSynthetic = 0x1000,
	isAnnotation = 0x2000,
	isEnum = 0x4000,
	isModule = 0x8000,					-- dalvik: "unused"
}

-- .class field access flags
local fieldAccessFlags = {
	isPublic = 0x0001,
	isPrivate = 0x0002,
	isProtected = 0x0004,
	isStatic = 0x0008,
	isFinal = 0x0010,
	isVolatile = 0x0040,	-- 'isVolatile' for field, 'isBridge' for method
	isTransient = 0x0080,	-- 'isTransient' for field, 'isVarArgs' for method
	isSynthetic = 0x1000,
	isEnum = 0x4000,
}

-- .class method access flags
local methodAccessFlags = table{
	isPublic = 0x0001,
	isPrivate = 0x0002,
	isProtected = 0x0004,
	isStatic = 0x0008,
	isFinal = 0x0010,
	isSynchronized = 0x0020,	-- 'isSuper' for class, 'isSynchronzied' for method
	isBridge = 0x0040,	-- 'isVolatile' for field, 'isBridge' for method
	isVarArgs = 0x0080,	-- 'isTransient' for field, 'isVarArgs' for method
	isNative = 0x0100,
	isAbstract = 0x0400,
	isStrict = 0x0800,
	isSynthetic = 0x1000,
	isConstructor = 0x10000,			-- dalvik-only
	isDeclaredSynchronized = 0x20000,	-- dalvik-only
}

local function setFlagsToObj(obj, flagsValue, flagsTable)
	for flagName,value in pairs(flagsTable) do
		if bit.band(flagsValue, value) ~= 0 then
			obj[flagName] = true
		end
	end
end

-- opposite of setFlagsToObj above
local function getFlagsFromObj(t, flagsTable)
	local flagsValue = 0
	for flagName,value in pairs(flagsTable) do
		if t[flagName] then
			flagsValue = bit.bor(flagsValue, value)
		end
	end
	return flagsValue
end

return {
	deepCopy = deepCopy,
	prims = prims,
	infoForPrims = infoForPrims,
	primSigStrForName = primSigStrForName,
	getJNISig = getJNISig,
	sigStrToObj = sigStrToObj,
	splitMethodJNISig = splitMethodJNISig,
	classAccessFlags = classAccessFlags,
	primaryClassAccessFlags = primaryClassAccessFlags,
	nestedClassAccessFlags = nestedClassAccessFlags,
	fieldAccessFlags = fieldAccessFlags,
	methodAccessFlags = methodAccessFlags,
	setFlagsToObj = setFlagsToObj,
	getFlagsFromObj = getFlagsFromObj,
	toSlashSepName = toSlashSepName,
	toDotSepName = toDotSepName,
	toLSlashSepSemName = toLSlashSepSemName,
}
