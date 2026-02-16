local ffi = require 'ffi'
local assert = require 'ext.assert'
local JavaObject = require 'java.object'
local prims = require 'java.util'.prims

local ffiTypesForPrim = prims:mapi(function(name)
	local o = {}
	o.ctype = ffi.typeof('j'..name)
	o.array1Type = ffi.typeof('$[1]', o.ctype)
	o.ptrType = ffi.typeof('$*', o.ctype)
	return o, name
end):setmetatable(nil)


local JavaArray = JavaObject:subclass()
JavaArray.__name = 'JavaArray'

function JavaArray:init(args)
	JavaArray.super.init(self, args)

	-- right now jniEnv:_newArray passes in classpath as
	-- elemClassPath..'[]'
	-- so pick it out here
	-- better yet, use the arg
	-- TODO should I be switching all my stored "classpath"s over to JNI-signatures to handle prims as well, and to match with :getClass():getName() ?
	self._elemClassPath = args.elemClassPath
		or self._classpath:match'^(.*)%[%]$'
		or error("didn't provide JavaArray .elemClassPath, and .classpath "..tostring(self._classpath).." did not end in []")

	local ffiTypes = ffiTypesForPrim[self._elemClassPath]
	if ffiTypes then
		-- or TODO just save this up front for primitives
		self.elemFFIType = ffiTypes.ctype
		self.elemFFIType_1 = ffiTypes.array1Type
		self.elemFFIType_ptr = ffiTypes.ptrType
	end
end

function JavaArray:__len()
	return self._env._ptr[0].GetArrayLength(self._env._ptr, self._ptr)
end


local getArrayElementsField = prims:mapi(function(name)
	return 'Get'..name:sub(1,1):upper()..name:sub(2)..'ArrayElements', name
end):setmetatable(nil)

-- I'd override __index, but that will bring with it a world of hurt....
function JavaArray:_get(i)
	self._env:_checkExceptions()

	i = tonumber(i) or error("java array index expected number, found "..tostring(i))
	local getArrayElements = getArrayElementsField[self._elemClassPath]
	if getArrayElements then
		local arptr = self._env._ptr[0][getArrayElements](self._env._ptr, self._ptr, nil)
		if arptr == nil then error("array index null pointer exception") end
		-- TODO throw a real Java out of bounds exception
		if i < 0 or i >= #self then error("index out of bounds "..tostring(i)) end
		return ffi.cast(self.elemFFIType_ptr, arptr)[i]
	else
		local elemClassPath = self._elemClassPath
		return JavaObject.createObjectForClassPath(elemClassPath, {
			env = self._env,
			ptr = self._env._ptr[0].GetObjectArrayElement(self._env._ptr, self._ptr, i),
			classpath = elemClassPath,
		})
	end

	self._env:_checkExceptions()
end

local setArrayRegionField = prims:mapi(function(name)
	return 'Set'..name:sub(1,1):upper()..name:sub(2)..'ArrayRegion', name
end):setmetatable(nil)


function JavaArray:_set(i, v)
	self._env:_checkExceptions()

	i = tonumber(i) or error("java array index expected number, found "..tostring(i))
	local setArrayRegion = setArrayRegionField[self._elemClassPath]
	if setArrayRegion then
print(setArrayRegion, 'setting array at', i, 'to', v, self._elemClassPath)
		self._env._ptr[0][setArrayRegion](self._env._ptr, self._ptr, i, 1,
			self.elemFFIType_1(v)
		)
	else
		-- another one of these primitive array problems
		-- the setter will depend on what the underlying primitive type is.
		self._env._ptr[0].SetObjectArrayElement(
			self._env._ptr,
			self._ptr,
			i,
			self._env:_luaToJavaArg(v, self._elemClassPath)
		)
	end
	
	self._env:_checkExceptions()
end

return JavaArray
