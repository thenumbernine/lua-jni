local table = require 'ext.table'

local function remapArg(arg)
	if type(arg) == 'table' then return arg.ptr end
	return arg
end

local function remapArgs(...)
	if select('#', ...) == 0 then return end
	return remapArg(...), remapArgs(select(2, ...))
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
		or 'L'..s..';'
	)
end
function getJNISigMethod(sig)
	return '('
		..table.sub(sig, 2)
			:mapi(getJNISig)
			:concat()
	..')'..getJNISig(sig[1] or 'void')
end

return {
	remapArg = remapArg,
	remapArgs = remapArgs,
	prims = prims,
	getJNISig = getJNISig,
}
