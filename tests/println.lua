#!/usr/bin/env luajit
local J = require 'java'
print('J', J)
print('J.System', J.System)
print('J.System.out', J.System.out)
local System = J.System
System.out:println("System.out.println works")
