local ffi = require 'ffi'
local JavaObject = require 'java.object'

local JavaString = JavaObject:subclass()
JavaString.__name = 'JavaString'

function JavaString:__tostring()
	local env = self._env
	local str = env._ptr[0].GetStringUTFChars(env._ptr, self._ptr, nil)
	local luastr = str ~= nil and ffi.string(str) or '(null)'
	env._ptr[0].ReleaseStringUTFChars(env._ptr, self._ptr, str)
	return luastr
end

function JavaString:__len()
	local env = self._env
	return env._ptr[0].GetStringLength(env._ptr, self._ptr)
end

return JavaString
