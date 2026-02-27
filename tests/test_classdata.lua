#!/usr/bin/env luajit

-- test reading classdata

local JavaClassData = require 'java.classdata'

-- make sure it's built
require 'java.build'.java{
	dst = 'Test.class',
	src = 'Test.java',
}

local cldata = JavaClassData:fromFile'Test.class'
print(require'ext.tolua'(cldata))
