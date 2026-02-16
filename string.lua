local ffi = require 'ffi'
local JavaObject = require 'java.object'

local JavaString = JavaObject:subclass()
JavaString.__name = 'JavaString'

function JavaString:__tostring()
	local str = self._env._ptr[0].GetStringUTFChars(self._env._ptr, self._ptr, nil)
	local luastr = str ~= nil and ffi.string(str) or '(null)'
	self._env._ptr[0].ReleaseStringUTFChars(self._env._ptr, self._ptr, str)
	return luastr
end

function JavaString:__len()
	return self._env._ptr[0].GetStringLength(self._env._ptr, self._ptr)
end

return JavaString
