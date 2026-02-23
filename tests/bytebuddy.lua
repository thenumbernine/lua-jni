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
local ByteBuddy = J.net.bytebuddy.ByteBuddy
print('ByteBuddy', ByteBuddy)
assert.is(ByteBuddy, require 'java.class', "I can't find the ByteBuddy jar...")

local _java_lang_Object = J.java.lang.Object:_class()
print('java.lang.Object', _java_lang_Object)

local bb = ByteBuddy()
print('bb', bb)
assert.is(bb, require 'java.object', "failed to instanciate ByteBuddy")

print('bb.subclass', bb.subclass)
os.exit()

bb = bb:subclass(_java_lang_Object)

bb = bb:method(J.net.bytebuddy.matcher.ElementMatchers:named'toString')
bb = bb:intercept(J.net.bytebuddy.implementation.FixedValue:value'Hello World!')
bb = bb:make()
bb = bb:load(_java_lang_Object:getClassLoader())
local dynamicType = bb:getLoaded()
print(dynamicType:getDeclaredConstructor():newInstance():toString())
