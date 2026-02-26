#!/usr/bin/env luajit
--[[
Me testing ByteBuddy for runtime class-creation so I can add subclass and lambda support...
https://repo1.maven.org/maven2/net/bytebuddy/byte-buddy/
https://repo1.maven.org/maven2/net/bytebuddy/byte-buddy-android/

here's the https://bytebuddy.net hello-world example:

it turns out it's a big example, because my call resolver is having trouble matching generics right now
--]]
local J = require 'java.vm'{
	props = {
		['java.class.path'] = table.concat({
			'byte-buddy-1.18.5.jar',
			'.',
		}, ':'),
	},
}.jniEnv
assert(require 'java.class':isa(J.net.bytebuddy.ByteBuddy), "I can't find the ByteBuddy jar...")

local dynamicType = J.net.bytebuddy.ByteBuddy()
	:subclass(J.Object.class)
	:method(J.net.bytebuddy.matcher.ElementMatchers:named'toString')
	:intercept(J.net.bytebuddy.implementation.FixedValue:value'Hello World!')
	:make()
	:load(J.Object.class:getClassLoader())
	:getLoaded()

-- now dynamicType is a Java object of type Class<?>, where the ? is Object because that's what I fed into :subclass() and :load() above
print('dynamicType', dynamicType, dynamicType._classpath)
local dynamicObj = dynamicType:getDeclaredConstructor():newInstance()
print('dynamicObj', dynamicObj)
