local assert = require 'ext.assert'
local class = require 'ext.class'

local JavaCallResolve = class()

function JavaCallResolve:init(options)
	self._options = assert(options)
end

function JavaCallResolve:__call(...)
	local option = JavaCallResolve.resolve(self._options, ...)
	return option(...)
end

-- static method, used by JavaClass.__new also
function JavaCallResolve.resolve(options, ...)
	-- ok now ...
	-- we gotta match up ... args with all the method option arsg
	-- TODO

	local option = options[1]

	return option
end

return JavaCallResolve
