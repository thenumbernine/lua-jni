#!/usr/bin/env luajit
local assert = require 'ext.assert'
local table = require 'ext.table'
local J = require 'java'

print('boolean', J.boolean)
print('byte', J.byte)
print('char', J.char)
print('short', J.short)
print('int', J.int)
print('long', J.long)
print('float', J.float)
print('double', J.double)


print('java.lang.Class.forName"java.lang.Class"', J.Class:forName'java.lang.Class')
assert.eq(J.java.lang.Class:forName'java.lang.Class', J.Class:forName'java.lang.Class')
print('java.lang.Class.forName"java.lang.Void"', J.Class:forName'java.lang.Void')

local Void = J.Void
print('Void', Void)
print('Void._ptr', Void._ptr)
assert.eq(J.Void, J.Void)

print('Void.TYPE', Void.TYPE)
print('Void.TYPE._ptr', Void.TYPE._ptr)
assert.eq(J.Void.TYPE, J.Void.TYPE)

-- Void.TYPE.getName() returns "void"
print('Void.TYPE:getName()', Void.TYPE:getName())
-- are prim names recognized at global in the Java namespace via FindClass?
print('J.void', J.void)
-- ... no, they are not.
-- why it would help if they are?
-- because signature resolution, especially for IsInstanceOf checking

-- Void.TYPE is not Void
-- what's the difference again?
--print(Void.TYPE == Void)

-- in java:
-- int.class == java.lang.Integer.TYPE
-- void.class == java.lang.Void.TYPE

-- so Class.forPrimitiveName'int' == Integer.TYPE ...
local Class = J.Class
assert(rawequal(J.Class, J._java_lang_Class))	-- make sure the cache works

--print(Class:forPrimitiveName'int')
--[[ TODO this is static, why can't I see it?
print('Class:')
for _,name in ipairs(table.keys(Class._members):sort()) do
	local membersForName = Class._members[name]
	print('', name, #membersForName)
end
-- ahhhaa
-- because it's a Java v22 method
-- and I'm using Java v21
--]]


-- array tests

local doubleArr = J:_newArray('double', 5)
print('doubleArr', doubleArr)
print('doubleArr:_getClass()', doubleArr:_getClass())	-- wait, this returns "char[]", probably because that was given to jniEnv to create the array
print('doubleArr._getClass()._name()', doubleArr:_getClass():_name())	-- "double[]"
print('doubleArr:_getClass():_super()', doubleArr:_getClass():_super())
--print('doubleArr:_super()', doubleArr:_super())

doubleArr[2] = 2*math.pi
print('doubleArr[2]', doubleArr[2])
doubleArr:_set(3, 3.14)
print('doubleArr[3]', doubleArr:_get(3))

print'double iter:'
for x in doubleArr:_iter() do print(x) end

local charArr = J:_newArray('char', 2)
charArr:_set(0, 100)
charArr:_set(1, 101)
--print('charArr[2]', charArr:_get(2))	-- exception
print('charArr[0]', charArr:_get(0))
print('charArr[1]', charArr:_get(1))
print('charArr[0]', charArr[0])
print('charArr[1]', charArr[1])

print('#charArr', #charArr)
print('charArr.length', charArr.length)
print('charArr:_getClass()._members.length', charArr:_getClass()._members.length)
print('charArr:_getClass()', charArr:_getClass())	-- wait, this returns "char[]", probably because that was given to jniEnv to create the array
print('charArr:_getClass():_name()', charArr:_getClass():_name())
print('charArr:_getClass():_super()', charArr:_getClass():_super())
--print('J.Array', J.Array)


