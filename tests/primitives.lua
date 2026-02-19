#!/usr/bin/env luajit
local assert = require 'ext.assert'
local table = require 'ext.table'
local J = require 'java'

print('java.lang.Class.forName"java.lang.Class"', J.java.lang.Class:forName'java.lang.Class')
assert.eq(J.java.lang.Class:forName'java.lang.Class', J.java.lang.Class:forName'java.lang.Class')
print('java.lang.Class.forName"java.lang.Void"', J.java.lang.Class:forName'java.lang.Void')

local Void = J.java.lang.Void
print('Void', Void)
print('Void._ptr', Void._ptr)
assert.eq(J.java.lang.Void, J.java.lang.Void)

print('Void.TYPE', Void.TYPE)
print('Void.TYPE._ptr', Void.TYPE._ptr)
assert.eq(J.java.lang.Void.TYPE, J.java.lang.Void.TYPE)

-- Void.TYPE.getName() returns "void"
-- prim names are recognized at global in the Java namespace?
print('Void.TYPE:getName()', Void.TYPE:getName())

-- Void.TYPE is not Void
-- what's the difference again?
--print(Void.TYPE == Void)

-- in java:
-- int.class == java.lang.Integer.TYPE
-- void.class == java.lang.Void.TYPE

-- so Class.forPrimitiveName'int' == Integer.TYPE ...
local Class = J.java.lang.Class
assert(rawequal(J.java.lang.Class, J._java_lang_Class))

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
