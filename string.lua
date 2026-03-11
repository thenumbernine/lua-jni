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
JavaString.super = nil
JavaString.class = nil
JavaString.subclass = nil
--JavaString.isa = nil -- handled in __index
--JavaString.isaSet = nil -- handled in __index

function JavaString:__tostring()
	return self._env:_fromJString(self._ptr) or '(null)'
end

return JavaString
