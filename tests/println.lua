#!/usr/bin/env luajit
local J = require 'java'
print('J', J)
print('J.java', J.java)
print('J.java.lang', J.java.lang)
print('J.java.lang.System', J.java.lang.System)
print('J.java.lang.System.out', J.java.lang.System.out)
print('J.java.lang.System.out.println', J.java.lang.System.out.println)
local System = J.java.lang.System
System.out:println("System.out.println works")
