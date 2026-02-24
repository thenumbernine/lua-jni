#!/usr/bin/env luajit
local tolua = require 'ext.tolua'
local jvm = require 'java.vm'()
-- Funny, this gives back 0x150000 for 1.5 I guess?  But Android Java gives back 0x10006 for 1.6 I guess, in their GLES style of 0x300002 representing GLES 3.2?
local J = jvm.jniEnv
print('J:_version()', ('0x%x'):format(J:_version()))
local props = J.System:getProperties()
for key in props:keySet():_iter() do
	print('', key, tolua(tostring(props:getProperty(key))))
end
