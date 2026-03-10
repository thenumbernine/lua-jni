#!/usr/bin/env luajit
local J = require 'java'

require 'java.build'.java{
	src = 'InnerClassTest.java',
	dst = 'InnerClassTest.class',
}

print('InnerClassTest', J.InnerClassTest)

-- [[ the manual way? 
local cl = J:_findClass'InnerClassTest$InnerClass'
print('InnerClassTest.InnerClass', cl)
--]]

-- [[ ok it works now
print('InnerClassTest.InnerClass', J.InnerClassTest.InnerClass)
--]]
