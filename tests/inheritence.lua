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
print('B', B)	-- JNIEnv->FindClass("B") comes back as 'char', because 'B' is the signature for 'byte', whose ctype is 'jbyte' which is typedef'd to 'char'
print('C', C)	-- JNIEnv->FindClass("C") comes back as 'unsigned short', because 'C' is the signature for 'char', whose ctype is 'jchar' which is typedef'd to 'unsigned short'
os.exit()

print('A isAssignableFrom A', A:_isAssignableFrom(A))
print('A isAssignableFrom B', A:_isAssignableFrom(B))
print('A isAssignableFrom C', A:_isAssignableFrom(C))

print('B isAssignableFrom A', B:_isAssignableFrom(A))
print('B isAssignableFrom B', B:_isAssignableFrom(B))
print('B isAssignableFrom C', B:_isAssignableFrom(C))

print('C isAssignableFrom A', C:_isAssignableFrom(A))
print('C isAssignableFrom B', C:_isAssignableFrom(B))
print('C isAssignableFrom C', C:_isAssignableFrom(C))

local a = A()
local b = B()
local c = C()

print()
print(require 'java.object':isa(a), require 'java.class':isa(a))
print('want true:', J._ptr[0].IsSameObject(J._ptr, J._ptr[0].GetObjectClass(J._ptr, a._ptr), A._ptr))
print(a:_getClass())
print('want true:', a:_getClass() == A)

print()
print(require 'java.object':isa(b), require 'java.class':isa(b))
print('want true:', J._ptr[0].IsSameObject(J._ptr, J._ptr[0].GetObjectClass(J._ptr, b._ptr), B._ptr))
print(b:_getClass())
print('want true:', b:_getClass() == B)

print()
print(require 'java.object':isa(c), require 'java.class':isa(c))
print('want true:', J._ptr[0].IsSameObject(J._ptr, J._ptr[0].GetObjectClass(J._ptr, c._ptr), C._ptr))
print(c:_getClass())
print('want true:', c:_getClass() == C)
os.exit()

print('a:toString()', a:toString())
print('b:toString()', b:toString())	-- "char" has no member named _members
print('c:toString()', c:toString())	-- "unsigned short" has no member named _members

print('a', a)
print('b', b)	-- error
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
