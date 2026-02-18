#!/usr/bin/env luajit
local J = require 'java'
local System = J.java.lang.System
System.out:println("System.out.println works")
