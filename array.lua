local ffi = require 'ffi'
local assert = require 'ext.assert'
local class = require 'ext.class'
local JavaObject = require 'java.object'
local prims = require 'java.util'.prims
local infoForPrims = require 'java.util'.infoForPrims


local super = JavaObject
local JavaArray = class(super)
JavaArray.__name = 'JavaArray'
JavaArray.__index = JavaObject.__index	-- class() will override this, so reset it
JavaArray.super = nil
JavaArray.class = nil
JavaArray.subclass = nil
--JavaArray.isa = nil -- TODO
--JavaArray.isaSet = nil -- TODO

--[[
args:
	elemClassPath
--]]
function JavaArray:init(args)
	-- self._classpath but thats in super which I can't call yet
	local _classpath = assert.index(args, 'classpath')

	-- right now jniEnv:_newArray passes in classpath as
	-- elemClassPath..'[]'
	-- so pick it out here
	-- better yet, use the arg
	-- TODO should I be switching all my stored "classpath"s over to JNI-signatures to handle prims as well, and to match with .getClass().getName() ?
	self._elemClassPath = args.elemClassPath
		or _classpath:match'^(.*)%[%]$'
		or error("didn't provide JavaArray .elemClassPath, and .classpath "..tostring(_classpath).." did not end in []")

	local primInfo = infoForPrims[self._elemClassPath]
	if primInfo then
		-- or TODO just save this up front for primitives
		self._elemFFIType = primInfo.ctype
		self._elemFFIType_1 = primInfo.array1Type
		self._elemFFIType_ptr = primInfo.ptrType
	end

	-- do super last because it write-protects the object for java namespace lookup __newindex
	super.init(self, args)
	local JavaObject__newindex = getmetatable(self).__newindex
	getmetatable(self).__newindex = function(self, k, v)
		if type(k) == 'number' then
			return self:_set(k, v)
		end
		JavaObject__newindex(self, k, v)
	end
end

local getArrayElementsField = prims:mapi(function(name)
	return 'Get'..name:sub(1,1):upper()..name:sub(2)..'ArrayElements', name
end):setmetatable(nil)

local releaseArrayElementsField = prims:mapi(function(name)
	return 'Release'..name:sub(1,1):upper()..name:sub(2)..'ArrayElements', name
end):setmetatable(nil)

-- I'd override __index, but that will bring with it a world of hurt....
function JavaArray:_get(i)
	local env = self._env

	env:_checkExceptions()

	i = tonumber(i) or error("java array index expected number, found "..tostring(i))
	-- TODO throw a real Java out of bounds exception
	if i < 0 or i >= #self then error("index out of bounds "..tostring(i)) end

	local getArrayElements = getArrayElementsField[self._elemClassPath]
	if getArrayElements then
		local releaseArrayElements = releaseArrayElementsField[self._elemClassPath]
		local arptr = env._ptr[0][getArrayElements](env._ptr, self._ptr, nil)
		if arptr == nil then error("array index null pointer exception") end
		local result = ffi.cast(self._elemFFIType_ptr, arptr)[i]
		env._ptr[0][releaseArrayElements](env._ptr, self._ptr, arptr, 0)
		return result
	else
		local elemClassPath = self._elemClassPath
		return JavaObject._createObjectForClassPath{
			env = env,
			ptr = env._ptr[0].GetObjectArrayElement(env._ptr, self._ptr, i),
			classpath = elemClassPath,
		}
	end

	env:_checkExceptions()
end

local setArrayRegionField = prims:mapi(function(name)
	return 'Set'..name:sub(1,1):upper()..name:sub(2)..'ArrayRegion', name
end):setmetatable(nil)

function JavaArray:_set(i, v)
	local env = self._env

	env:_checkExceptions()

	i = tonumber(i) or error("java array index expected number, found "..tostring(i))
	if i < 0 or i >= #self then error("index out of bounds "..tostring(i)) end

	local setArrayRegion = setArrayRegionField[self._elemClassPath]
	if setArrayRegion then
--DEBUG:print(setArrayRegion, 'setting array at', i, 'to', v, self._elemClassPath)
		env._ptr[0][setArrayRegion](env._ptr, self._ptr, i, 1,
			self._elemFFIType_1(v)
		)
	else
		-- another one of these primitive array problems
		-- the setter will depend on what the underlying primitive type is.
		env._ptr[0].SetObjectArrayElement(
			env._ptr,
			self._ptr,
			i,
			env:_luaToJavaArg(v, self._elemClassPath)
		)
	end

	env:_checkExceptions()
end

function JavaArray:_map()
	local getArrayElements = getArrayElementsField[self._elemClassPath]
	if not getArrayElements then
		error("JavaArray:_map() only works for primitives, found "..tostring(self._elemClassPath))
	end

	local envptr = self._env._ptr
	local arptr = envptr[0][getArrayElements](envptr, self._ptr, nil)
	if arptr == nil then error("array null pointer exception") end

	return ffi.cast(self._elemFFIType_ptr, arptr)
end

function JavaArray:_unmap(arptr)
	assert.type(arptr, 'cdata', "_unmap expected pointer")
	local releaseArrayElements = releaseArrayElementsField[self._elemClassPath]
	if not releaseArrayElements then
		error("JavaArray:_unmap() only works for primitives, found "..tostring(self._elemClassPath))
	end

	local envptr = self._env._ptr
	envptr[0][releaseArrayElements](envptr, self._ptr, arptr, 0)
end

local function unpackLocal(ar, i, n)
	if i >= n then return end
	return ar[i], unpackLocal(ar, i+1, n)
end

function JavaArray:_unpack()
	local n = #self
	return unpackLocal(self, 0, n)
end

function JavaArray:__index(k)
	local v = JavaArray[k]
	if v ~= nil then return v end

	if type(k) == 'number' then
		return self:_get(k)
	end

	-- fallthrough to array fields in JavaObject's __index
	return super.__index(self, k)
end

return JavaArray
