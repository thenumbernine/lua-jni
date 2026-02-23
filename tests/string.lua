#!/usr/bin/env luajit
local assert = require 'ext.assert'
local table = require 'ext.table'
local tolua = require 'ext.tolua'

-- string test
local J = require 'java'
print('J', J)
print('J.java', J.java)
print('J.java.lang', J.java.lang)
local String = J.java.lang.String
print('java.lang.String', String)

local String2 = J:_findClass'java.lang.String'
print('J:_findClass"java.lang.String"', String2)
assert.eq(String, String2)

print('String:_isAssignableFrom(String)', String:_isAssignableFrom(String))

--[[ show all contents
print'String:'
for _,name in ipairs(table.keys(String._members):sort()) do
	local membersForName = String._members[name]
	print('', name, #membersForName)
	for _,option in ipairs(membersForName) do
		print('','',option)
	end
end
--]]

-- can I make a new String?
-- chicken-and-egg, you have to use JNIEnv
local s = J:_str'new string'
print('s lua-isa java.string', require 'java.string':isa(s))
print('s = new string', s)
print('s:_getClass()', s:_getClass())
assert.eq(s:_getClass(), String)
print('s:_getClass():_getDebugStr()', s:_getClass():_getDebugStr())
print('s:_getClass():_name()', s:_getClass():_name())

print('s.join',  s.join)

print('#s', #s)
print('s.length', s.length)	-- turns out string.length is syntactic sugar for string.length()
print('s:length()', s:length())
print('#s:_getClass()._members.length', #s:_getClass()._members.length)
print('s:_getClass()._members.length[1]._sig', tolua(s:_getClass()._members.length[1]._sig))


-- can I make an array of Strings?
local arr = J:_newArray('java.lang.String', 3)
print('arr String[3]', arr)
print('arr:_getClass():_name()', arr:_getClass():_name())	-- [Ljava/lang/String; ... i.e. String[]
-- can I get its length?
print('#(arr String[3])', #arr)

arr:_set(0, 'a')
arr:_set(1, 'b')
arr:_set(2, 'c')

print('arr[0]', arr:_get(0))
print('arr[1]', arr:_get(1))
print('arr[2]', arr:_get(2))
arr[1] = J:_str'testing'
print('arr[0]', arr[0])
print('arr[1]', arr[1])
print('arr[2]', arr[2])

-- [[ needs this to work
print('java.lang.String', J:_findClass'java.lang.String')
-- [=[ so FindClass accepts signature based Ljava/lang/String; and just regular slash-separated java/lang/String ...
local String1 = J._ptr[0].FindClass(J._ptr, 'Ljava/lang/String;')
print('java.lang.String[] from JNIEnv->FindClass("Ljava/lang/String;")', String1)
local String2 = J._ptr[0].FindClass(J._ptr, 'java/lang/String')
print('java.lang.String[] from JNIEnv->FindClass("java/lang/String")', String2)
print('same?', J._ptr[0].IsSameObject(J._ptr, String1, String2))
--]=]
print('java.lang.String[] from String.class.arrayType()', J.java.lang.String:_class():arrayType())
print('java.lang.String[] from J:_findClass()', J:_findClass'java.lang.String[]')
print('java.lang.String[] from JNIEnv->FindClass("[Ljava/lang/String;")', J._ptr[0].FindClass(J._ptr, '[Ljava/lang/String;'))
--print('JNIEnv->FindClass("I")', J._ptr[0].FindClass(J._ptr, 'I'))
--print('JNIEnv->FindClass("int")', J._ptr[0].FindClass(J._ptr, 'int'))
print(J:_newArray('java.lang.String[][][]', 0))
--]]

print'DONE'
