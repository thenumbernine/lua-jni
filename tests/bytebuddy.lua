#!/usr/bin/env luajit
--[[
Me testing ByteBuddy for runtime class-creation so I can add subclass and lambda support...
https://repo1.maven.org/maven2/net/bytebuddy/byte-buddy/
https://repo1.maven.org/maven2/net/bytebuddy/byte-buddy-android/

here's the https://bytebuddy.net hello-world example:
--]]
local table = require 'ext.table'
local assert = require 'ext.assert'
local jvm = require 'java.vm'{
	props = {
		['java.class.path'] = table{
			'byte-buddy-1.18.5.jar',
			'.',
		}:concat':',
		--['java.library.path'] = '.',
	},
}
local J = jvm.jniEnv
assert.is(J.net.bytebuddy.ByteBuddy, require 'java.class', "I can't find the ByteBuddy jar...")

local class_java_lang_Object = J.java.lang.Object
local objOfClass_java_lang_Object = class_java_lang_Object:_class()
local dynamicType = J.net.bytebuddy.ByteBuddy()
	:subclass(objOfClass_java_lang_Object)
	:method(J.net.bytebuddy.matcher.ElementMatchers:named'toString')
	:intercept(J.net.bytebuddy.implementation.FixedValue:value'Hello World!')
	:make()
	:load(objOfClass_java_lang_Object:getClassLoader())
	:getLoaded()

-- now dynamicType is a Java object of type java.lang.Class<java.lang.Object>
print('dynamicType', dynamicType, dynamicType._classpath)

--[[ "failed to find a matching signature for function getDeclaredConstructor"
--print(dynamicType:_getClass()._members.getDeclaredConstructor[1]) -- works
--print(dynamicType.getDeclaredConstructor) -- works
print(dynamicType:getDeclaredConstructor():newInstance():toString())
--]]
-- [[
local dynamicTypeClass = dynamicType:_getClass()
--print(table.keys(dynamicTypeClass._members):sort():concat', ')
--print(dynamicTypeClass._members.getDeclaredConstructor)
--print(#dynamicTypeClass._members.getDeclaredConstructor)
--print(dynamicTypeClass._members.getDeclaredConstructor[1])
-- local dynamicTypeCtor = dynamicType:getDeclaredConstructor()	 -- "failed to find a matching signature"
-- TODO TODO TODO WHY CAN'T CALL RESOLVER MATCH THE SIGNATURES?
local dynamicTypeCtor = dynamicTypeClass._members.getDeclaredConstructor[1](dynamicType)
print(dynamicTypeCtor)
print(dynamicTypeCtor._classpath)
print(dynamicTypeCtor.newInstance)
--print(dynamicTypeCtor:newInstance()) -- "failed to find a matching signature"
local dynamicTypeCtorClass = dynamicTypeCtor:_getClass()
print(dynamicTypeCtorClass)
print(dynamicTypeCtorClass._members.newInstance[1])
local dynamicObjInst = dynamicTypeCtorClass._members.newInstance[1](dynamicTypeCtor)
print(dynamicObjInst)
--]]
