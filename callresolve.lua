local assert = require 'ext.assert'
local class = require 'ext.class'
local string = require 'ext.string'
local table = require 'ext.table'


local JavaCallResolve = class()
JavaCallResolve.__name = 'JavaCallResolve'

-- static methods or ctors need the 1st arg to be the class
-- otherwise 1st arg mst be an object
-- if you try to pass a class to a non-static method then JNI just segfaults
function JavaCallResolve:init(args)
	self._name = assert.index(args, 'name')
	self._caller = assert.index(args, 'caller')
	self._options = assert.index(args, 'options')
end

function JavaCallResolve:__call(...)
	-- TODO don't convert ... twice from Lua to Java
	return assert(JavaCallResolve.resolve(self._name, self._options, ...))(...)
end

-- static method, used by JavaClass.__new also
function JavaCallResolve.resolve(name, options, thisOrClass, ...)
	local env = thisOrClass._env

	-- ok now ...
	-- we gotta match up ... args with all the method option arsg

	local numArgs = select('#', ...)
	local bestOption
	local bestSigDist = math.huge
	for i,option in ipairs(options) do
		local sig = option._sig
		local sigDist

		local doMatch

		-- if it's a vararg then it still has a list of all non-varargs to match
		-- then it has to match the varargs as whatever type the vararg should be
		if option._isVarArgs then
			if numArgs >= #sig-2 then	-- #sig-2 is the # of non-varargs that we need to match
				local sigLast = sig[#sig]
				local sigVarArgBase = sigLast:match'^(.*)%[%]$'
				sig = table(sig)
				for i=#sig,numArgs+1 do
					sig[i] = sigVarArgBase
				end
				doMatch = true
				-- TODO eventually test each vararg type to the underlying vararg array type
			end
		else
			if #sig-1 == numArgs then
				doMatch = true
			end
		end
			
		-- sig[1] is the return type
		-- call args #1 is the this-or-class
		-- the rest will match up
		if doMatch then
			-- now test if casting works ...
			-- TODO calc score from dist of classes
			sigDist = 0
			for i=1,numArgs do
--DEBUG:print('arg #'..i..' = '..tostring((select(i, ...))))
--DEBUG:print('vs sig', sig[i+1])
				local canConvert, argDist = env:_canConvertLuaToJavaArg(
					select(i, ...),
					sig[i+1]
				)
				if not canConvert then
					sigDist = nil
					break
				end
				if argDist then
					sigDist = sigDist + argDist
				end
			end
		end

		-- alright at this point it just picks the last matching signature
		-- but I should be scoring them by how far apart in the class tree the type coercion is
		-- and somehow I should factor in differences of prim types

		if sigDist then
			-- TODO calculate score based on how far away coercion is
			-- score by difference-in-size of prim args or difference-in-class-tree of classes
			if bestSigDist > sigDist then
				bestSigDist = sigDist
				bestOption = option
			end
		end
	end

	if not bestOption then
		return nil, "failed to find a matching signature for function "..name
	end

	return bestOption
end

function JavaCallResolve:__tostring()
	return self.__name..'('..table.mapi(self._options, tostring):concat', '..')'
end

JavaCallResolve.__concat = string.concat

return JavaCallResolve
