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
	self._caller = assert.index(args, 'caller')
	self._options = assert.index(args, 'options')
end

function JavaCallResolve:__call(...)
	-- TODO don't convert ... twice
	return assert(JavaCallResolve.resolve(self._options, ...))(...)
end

-- static method, used by JavaClass.__new also
function JavaCallResolve.resolve(options, thisOrClass, ...)
	-- ok now ...
	-- we gotta match up ... args with all the method option arsg

	local JavaClass = require 'java.class'
	local calledWithClass = JavaClass:isa(thisOrClass)
	local triedToCallMemberMethodWithAClass

	local numArgs = 1 + select('#', ...)
	local bestOption
	local bestScore = math.huge
	for i,option in ipairs(options) do
		-- sig[1] is the return type
		-- call args #1 is the this-or-class
		-- the rest will match up
		if #option._sig == numArgs then
			local optionIsCtor = option._isCtor

			local consider
			if calledWithClass then
				local methodAcceptsClass = option._static or optionIsCtor	-- only static or ctor can handle class as 1st arg
				if methodAcceptsClass then
					consider = true
				else
					triedToCallMemberMethodWithAClass = true
				end
			else
				local methodAcceptsObject = not optionIsCtor				-- static or non-static accept objects, but not ctors
				if methodAcceptsObject then
					consider = true
				end
			end

			if consider then
				-- TODO calculate score based on how far away coercion is
				local score = 0
				if score < bestScore then
					bestScore = score
					bestOption = option
				end
			end
		end
	end

	if not bestOption then
		if triedToCallMemberMethodWithAClass then
			return nil, "tried to call a member method with a class"
		else
			return nil, "failed to find a matching prototype"
		end
	end

	return bestOption
end

function JavaCallResolve:__tostring()
	return self.__name..'('..table.mapi(self._options, tostring):concat', '..')'
end

JavaCallResolve.__concat = string.concat

return JavaCallResolve
