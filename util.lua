local ffi = require 'ffi'
local table = require 'ext.table'
local assert = require 'ext.assert'

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

local ffiTypesForPrim = prims:mapi(function(name)
	local o = {}
	o.ctype = ffi.typeof('j'..name)
	o.array1Type = ffi.typeof('$[1]', o.ctype)
	o.ptrType = ffi.typeof('$*', o.ctype)
	return o, name
end):setmetatable(nil)

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

-- opposite of getJNISig
local function sigStrToObj(s)
	s = tostring(s)
--DEBUG:print('sigStrToObj', s)	
	assert(not s:match'^%(', "TODO sigStrToobject for methods")
	local arraySuffix = ''
	while true do
		local rest = s:match'^%[(.*)$'
		if not rest then break end
		arraySuffix = arraySuffix .. '[]'
		s = rest
	end
--DEBUG:print('arrays', arraySuffix, 'base', s)

	local prim = primNameForSigStr[s]
	if prim then 
--DEBUG:print'is prim'		
		-- TOOD match and return the rest
		return prim..arraySuffix 
	end
--DEBUG:print('should be class', s)	
	-- what's left? objects?
	local classpath, rest = s:match'^L([^;]*);(.*)$'
--DEBUG:print('classpath', classpath)	
	if classpath then
		-- convert from /-separator when it is to .-separator
		classpath = classpath:gsub('/', '%.')
		assert.eq(rest, '')
--DEBUG:print('returning', 	classpath..arraySuffix)
		return classpath..arraySuffix 
	end
	return nil --error("sigStrToObj "..tostring(s))
end

return {
	prims = prims,
	ffiTypesForPrim = ffiTypesForPrim,
	getJNISig = getJNISig,
	sigStrToObj = sigStrToObj,
}
