local class = require 'ext.class'
local assert = require 'ext.assert'
local string = require 'ext.string'

local JavaObject = class()
JavaObject.__name = 'JavaObject' 

function JavaObject:init(args)
	self.env = assert.index(args, 'env')
	self.ptr = assert.index(args, 'ptr')
	
	-- TODO detect if not provided?
	self.classpath = assert.index(args, 'classpath')
end

function JavaObject:__tostring()
	return self.__name..'('..tostring(self.ptr)..')'
end

JavaObject.__concat = string.concat

-- static helper function for getting the correct JavaObject subclass depending on the classpath
function JavaObject.getWrapper(classpath)
	if classpath == 'java.lang.String' then
		-- TODO I *could* fully-qualify all these in some directory namespace, that'd be the Java thing to do ....
		return require 'java.string'
	end
	return JavaObject
end

return JavaObject
