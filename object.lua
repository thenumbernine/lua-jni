local class = require 'ext.class'
local assert = require 'ext.assert'
local string = require 'ext.string'

local JavaObject = class()
JavaObject.__name = 'JavaObject'

function JavaObject:init(args)
	self._env = assert.index(args, 'env')
	self._ptr = assert.index(args, 'ptr')

	-- TODO detect if not provided?
	self._classpath = assert.index(args, 'classpath')

-- I would like to always save the class here
-- but for the bootstrap classes, they need to call java functions, which wrap Java object results
-- and those would reach here before the bootstrapping of classes is done,
-- so env:_class() wouldn't work
--	self._jclass = self._env:_class(self._classpath)
end

-- static helper
function JavaObject._getLuaClassForClassPath(classpath)
	if classpath == 'java.lang.String' then
		return require 'java.string'
	-- I can't tell how I should format the classpath
	elseif classpath:match'^%[' then
		error("dont' use jni signatures for classpaths")
		return require 'java.array'
	elseif classpath:match'%[%]$' then
		return require 'java.array'
	end
	return JavaObject
end

-- static helper function for getting the correct JavaObject subclass depending on the classpath
function JavaObject._createObjectForClassPath(classpath, args)
	return JavaObject._getLuaClassForClassPath(classpath)(args)
end

-- gets a JavaClass wrapping the java call `obj._class()`
function JavaObject:_class()
--DEBUG:print('	JavaObject:_class()')
	local env = self._env
	local classpath, jclass = env:_getObjClassPath(self._ptr)
--DEBUG:print('JavaObject:_class classpath='..classpath)
	--[[ always make a new one
	local classObj = env:_saveJClassForClassPath{ptr=jclass, classpath=classpath}
	--]]
	-- [[ write only if it exists
-- TODO problems FIXME
	local classObj = env._classesLoaded[classpath]
--DEBUG:if classObj then assert.eq(classObj._classpath, classpath) end
--DEBUG:print('classObj', classObj)
	if not classObj then
--DEBUG:print('!!! JavaObject._class creating JavaClass for classpath='..classpath)
		local JavaClass = require 'java.class'
		classObj = JavaClass{
			env = env,
			ptr = jclass,
			classpath = classpath,
		}
		classObj:_setupReflection()
--DEBUG:print('!!! JavaObject._class overwriting '..classpath..' with classObj '..classObj)
		env._classesLoaded[classpath] = classObj
assert.eq(classObj._classpath, classpath)
	end
	--]]
	return classObj
end

-- shorthand for self:_class():_method(args)
function JavaObject:_method(args)
	return self:_class():_method(args)
end

-- shorthand
function JavaObject:_field(args)
	return self:_class():_field(args)
end

-- calls in java `obj.toString()`
function JavaObject:_javaToString()
	return tostring(self:_method{
		name = 'toString',
		sig = {'java.lang.String'},
	}(self))
end

function JavaObject:_getDebugStr()
	return self.__name..'('
		..tostring(self._classpath)
		..' '
		..tostring(self._ptr)
		..')'
end

function JavaObject:__tostring()
	return self:_javaToString()
end

JavaObject.__concat = string.concat

-- [[
function JavaObject:__index(k)
	-- if self[k] exists then this isn't called
	local cl = getmetatable(self)
	local v = cl[k]
	if v ~= nil then return v end

	if type(k) ~= 'string' then return end

	-- don't build namespaces off private vars
	if k:match'^_' then
print('JavaObject.__index', k, "I am reserving underscores for private variables.  You were about to invoke a name resolve")
print(debug.traceback())
		return
	end

	-- now check fields/methods
	local classObj = self:_class()
--DEBUG:print('here', classObj._classpath)
--DEBUG:print(require'ext.table'.keys(classObj._members):sort():concat', ')
	local membersForName = classObj._members[k]
	if membersForName then
assert.gt(#membersForName, 0, k)		
--DEBUG:print('#membersForName', k, #membersForName)
		local JavaField = require 'java.field'
		local JavaMethod = require 'java.method'
		-- how to resolve
if #membersForName > 1 then print("for name "..k.." there are "..#membersForName.." options") end
		-- now if its a field vs a method ...
		local member = membersForName[1]
		if JavaField:isa(member) then
			return member:_get(self)	-- call the getter of the field
		elseif JavaMethod:isa(member) then
			-- TODO return the method in a state to call this object?
			-- or return a new wrapper for methods + call context of this object?
			-- or for now return a function that calls the method with this
			--if member._static then
				-- bind 1st arg to the object
			--	return function(...) return member(self, ...) end
			--else
				-- still wants self as 1st arg
				-- so you can use Lua's a.b vs a:b tricks
				return member	
			--end
		else
			error("got a member for field "..k.." with unknown type "..tostring(getmetatable(member).__name))
		end
	end
end
--]]

return JavaObject
