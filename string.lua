--[[
tempting to get rid of this.

just merge __len and __tostring with JavaObject ...
--]]
local ffi = require 'ffi'
local class = require 'ext.class'
local JavaObject = require 'java.object'

local JavaString = class(JavaObject)
JavaString.__name = 'JavaString'
JavaString.__index = JavaObject.__index	-- class() will override this, so reset it
JavaString.subclass = nil
--JavaString.isa = nil -- handled in __index
--JavaString.isaSet = nil -- handled in __index

function JavaString:__tostring()
	local envptr = self._env._ptr
	local str = envptr[0].GetStringUTFChars(envptr, self._ptr, nil)
	local luastr = str ~= nil and ffi.string(str) or '(null)'
	envptr[0].ReleaseStringUTFChars(envptr, self._ptr, str)
	return luastr
end

return JavaString
