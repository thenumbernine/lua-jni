local ffi = require 'ffi'
local JavaObject = require 'java.object'

local JavaString = JavaObject:subclass()
JavaString.__name = 'JavaString' 

function JavaString:__tostring()
	local str = self.env.ptr[0].GetStringUTFChars(self.env.ptr, self.ptr, nil)
	local luastr = str ~= nil and ffi.string(str) or '(null)'
	self.env.ptr[0].ReleaseStringUTFChars(self.env.ptr, self.ptr, str)
	return luastr
end

return JavaString
