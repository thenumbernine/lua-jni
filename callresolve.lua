local assert = require 'ext.assert'
local class = require 'ext.class'

local JavaCallResolve = class()

function JavaCallResolve:init(options)
	self._options = assert(options)
end

function JavaCallResolve:__call(...)
	-- TODO don't convert ... twice
	local option = JavaCallResolve.resolve(self._options, ...)
	return option(...)
end

-- static method, used by JavaClass.__new also
function JavaCallResolve.resolve(options, ...)
	-- ok now ...
	-- we gotta match up ... args with all the method option arsg

	local n = select('#', ...)
	local bestOption
	local bestScore = math.huge
	for i,option in ipairs(options) do
		-- sig[1] is the return type
		-- ...[1] is the this-or-class
		if #option._sig == n then
			-- TODO calculate score based on how far away coercion is
			local score = 0
			if score < bestScore then
				bestScore = score
				bestOption = option
			end
		end
	end
	return bestOption
end

return JavaCallResolve
