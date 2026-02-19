#!/usr/bin/env luajit

-- build java
local os = require 'ext.os'
local targets = require 'make.targets'()
for _,fn in ipairs{'A', 'B', 'C'} do
	targets:add{
		dsts = {fn..'.class'},
		srcs = {fn..'.java'},
		rule = function(r)
			assert(os.exec('javac '..r.srcs[1]))
		end,
	}
end
targets:runAll()

local J = require 'java'
local A, B, C = J.A, J.B, J.C
local Object = J.java.lang.Object

print('Object', Object)
print('A', A)
print('B', B)
print('C', C)

local a = A:_new()
local b = B:_new()
local c = C:_new()

print('a', a)
print('b', b)
print('c', c)

print('a instanceof A', a:_instanceof(A))
print('a instanceof B', a:_instanceof(B))
print('a instanceof C', a:_instanceof(C))

print('b instanceof A', b:_instanceof(A))
print('b instanceof B', b:_instanceof(B))
print('b instanceof C', b:_instanceof(C))

print('c instanceof A', c:_instanceof(A))
print('c instanceof B', c:_instanceof(B))
print('c instanceof C', c:_instanceof(C))
