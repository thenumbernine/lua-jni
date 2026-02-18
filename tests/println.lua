#!/usr/bin/env luajit
local J = require 'java'
print(J)
print(J.java)
print(J.java.lang)
print(J.java.lang.System)
print(J.java.lang.System.out)
local System = J.java.lang.System
System.out:println("System.out.println works")
