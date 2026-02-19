local ffi = require 'ffi'
local JavaObject = require 'java.object'

local JavaString = JavaObject:subclass()
JavaString.__name = 'JavaString'
JavaString.__index = JavaObject.__index	-- class() / :subclass() will override this, so reset it

function JavaString:__tostring()
	local envptr = self._env._ptr
	local str = envptr[0].GetStringUTFChars(envptr, self._ptr, nil)
	local luastr = str ~= nil and ffi.string(str) or '(null)'
	envptr[0].ReleaseStringUTFChars(envptr, self._ptr, str)
	return luastr
end

-- This is equivalent to Java's String.length fake-field which hides its String.length() member-method
-- but I guess it's a few less calls?
function JavaString:__len()
	local envptr = self._env._ptr
	return envptr[0].GetStringLength(envptr, self._ptr)
end

return JavaString
