local assert = require 'ext.assert'
local JavaObject = require 'java.object'
local prims = require 'java.util'.prims

local isPrimitive = prims:mapi(function(name)
	return true, name
end):setmetatable(nil)


local JavaArray = JavaObject:subclass()
JavaArray.__name = 'JavaArray'

function JavaArray:init(args)
	JavaArray.super.init(self, args)

	-- right now jniEnv:newArray passes in classpath as
	-- elemClassPath..'[]'
	-- so pick it out here
	-- better yet, use the arg
	-- TODO should I be switching all my stored "classpath"s over to JNI-signatures to handle prims as well, and to match with :getClass():getName() ?
	self.elemClassPath = assert.index(args, 'elemClassPath')
end

function JavaArray:__len()
	return self.env.ptr[0].GetArrayLength(self.env.ptr, self.ptr)
end


local getArrayElementsField = prims:mapi(function(name)
	return 'Get'..name:sub(1,1):upper()..name:sub(2)..'ArrayElements', name
end):setmetatable(nil)

-- I'd override __index, but that will bring with it a world of hurt....
function JavaArray:getElem(i)
	local getArrayElements = getArrayElementsField[self.elemClassPath]
	if getArrayElements then
		local arptr = self.env.ptr[0][getArrayElements](self.env.ptr, self.ptr, i)
		if arptr == nil then error("array index null pointer exception") end
		return ffi.cast(self.elemClassPath..'*', arptr)[i]
	else
		-- TODO what about primitives?
		-- where to store if this array is a primitive array vs an object array?
		-- in the classpath?
		-- aren't there subclasses of Array for different primitive-arrays?
		return JavaObject{
			env = self.env,
			ptr = self.env.ptr[0].GetObjectArrayElement(self.env.ptr, self.ptr, i),
			classpath = self.classpath:match'(.*)%[%]$' or '?',	-- TODO ...
		}
	end
end

local setArrayRegionField = prims:mapi(function(name)
	return 'Set'..name:sub(1,1):upper()..name:sub(2)..'ArrayRegion', name
end):setmetatable(nil)


function JavaArray:setElem(i, v)
	local setArrayRegion = setArrayRegionField[self.elemClassPath]
	if setArrayRegion then
		self.env.ptr[0][setArrayRegion](self.env.ptr, self.ptr, i, 1, 
			ffi.new(self.elemClassPath..'[1]', v)
		)
	else
		-- another one of these primitive array problems
		-- the setter will depend on what the underlying primitive type is.
		self.env.ptr[0].SetObjectArrayElement(self.env.ptr, self.ptr, i, v.ptr)
	end
end

return JavaArray
