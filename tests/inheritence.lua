#!/usr/bin/env luajit

-- build java
for _,fn in ipairs{'TestInheritenceA', 'TestInheritenceB', 'TestInheritenceC'} do
	require 'java.build'.java{
		src = fn..'.java',
		dst = fn..'.class',
	}
end

local J = require 'java'

--[[
Under my vanilla desktop Java:
JNIEnv->FindClass("B") comes back as 'char', because 'B' is the signature for 'byte', whose ctype is 'jbyte' which is typedef'd to 'char'
JNIEnv->FindClass("C") comes back as 'unsigned short', because 'C' is the signature for 'char', whose ctype is 'jchar' which is typedef'd to 'unsigned short'
The fix: to use signature names, i.e. "Ljava/lang/String;" etc or "LB;"
The problem with that?: Google Android implemented this function wrong and it segfaults upon getting a signature type.  It only accepts slash-separated types.
	Here is hoping stupid Google Android java doesn't convert signatures like Z B C S I J F D V to primtiives, or else its JNI FindClass is hiding Java root-namespace classes of matching names.
--]]
local Object = J.Object
print('Object', Object)
print('B', B)	
print('C', C)	



print("J:_findClass'TestInheritenceA'", J:_findClass'TestInheritenceA')
print("J:_findClass'TestInheritenceB'", J:_findClass'TestInheritenceB')
print("J:_findClass'TestInheritenceC'", J:_findClass'TestInheritenceC')

local TestInheritenceA = J.TestInheritenceA
local TestInheritenceB = J.TestInheritenceB
local TestInheritenceC = J.TestInheritenceC
print('J:_getJClassClasspath(TestInheritenceA._ptr)', J:_getJClassClasspath(TestInheritenceA._ptr))
print('J:_getJClassClasspath(TestInheritenceB._ptr)', J:_getJClassClasspath(TestInheritenceB._ptr))
print('J:_getJClassClasspath(TestInheritenceC._ptr)', J:_getJClassClasspath(TestInheritenceC._ptr))


print('TestInheritenceA', TestInheritenceA)
print('TestInheritenceB', TestInheritenceB)	
print('TestInheritenceC', TestInheritenceC)	

local a = TestInheritenceA()
local b = TestInheritenceB()
local c = TestInheritenceC()

-- J.TestInheritenceA is our TestInheritenceA class
-- J.TestInheritenceB
local jclass_a = J:_getObjClass(a._ptr)
local jclass_b = J:_getObjClass(b._ptr)
local jclass_c = J:_getObjClass(c._ptr)
print('J:_getObjClass(a._ptr)', jclass_a)
print('J:_getObjClass(b._ptr)', jclass_b)
print('J:_getObjClass(c._ptr)', jclass_c)

local jclass_a_sig = J:_getJClassClasspath(jclass_a)
local jclass_b_sig = J:_getJClassClasspath(jclass_b)
local jclass_c_sig = J:_getJClassClasspath(jclass_c)

print('J:_getJClassClasspath(J:_getObjClass(a._ptr))', jclass_a_sig)
print('J:_getJClassClasspath(J:_getObjClass(b._ptr))', jclass_b_sig)
print('J:_getJClassClasspath(J:_getObjClass(c._ptr))', jclass_c_sig)

print('a:_getClass()', a:_getClass())
print('b:_getClass()', b:_getClass())
print('c:_getClass()', c:_getClass())

print('TestInheritenceA isAssignableFrom TestInheritenceA', TestInheritenceA:_isAssignableFrom(TestInheritenceA))
print('TestInheritenceA isAssignableFrom TestInheritenceB', TestInheritenceA:_isAssignableFrom(TestInheritenceB))
print('TestInheritenceA isAssignableFrom TestInheritenceC', TestInheritenceA:_isAssignableFrom(TestInheritenceC))

print('TestInheritenceB isAssignableFrom TestInheritenceA', TestInheritenceB:_isAssignableFrom(TestInheritenceA))
print('TestInheritenceB isAssignableFrom TestInheritenceB', TestInheritenceB:_isAssignableFrom(TestInheritenceB))
print('TestInheritenceB isAssignableFrom TestInheritenceC', TestInheritenceB:_isAssignableFrom(TestInheritenceC))

print('TestInheritenceC isAssignableFrom TestInheritenceA', TestInheritenceC:_isAssignableFrom(TestInheritenceA))
print('TestInheritenceC isAssignableFrom TestInheritenceB', TestInheritenceC:_isAssignableFrom(TestInheritenceB))
print('TestInheritenceC isAssignableFrom TestInheritenceC', TestInheritenceC:_isAssignableFrom(TestInheritenceC))


print()
print(require 'java.object':isa(a), require 'java.class':isa(a))
print('want true:', J._ptr[0].IsSameObject(J._ptr, J._ptr[0].GetObjectClass(J._ptr, a._ptr), TestInheritenceA._ptr))
print(a:_getClass())
print('want true:', a:_getClass() == TestInheritenceA)

print()
print(require 'java.object':isa(b), require 'java.class':isa(b))
print('want true:', J._ptr[0].IsSameObject(J._ptr, J._ptr[0].GetObjectClass(J._ptr, b._ptr), TestInheritenceB._ptr))
print(b:_getClass())
print('want true:', b:_getClass() == TestInheritenceB)

print()
print(require 'java.object':isa(c), require 'java.class':isa(c))
print('want true:', J._ptr[0].IsSameObject(J._ptr, J._ptr[0].GetObjectClass(J._ptr, c._ptr), TestInheritenceC._ptr))
print(c:_getClass())
print('want true:', c:_getClass() == TestInheritenceC)

print('a:toString()', a:toString())
print('b:toString()', b:toString())
print('c:toString()', c:toString())

print('a', a)
print('b', b)	-- error
print('c', c)

print('a instanceof TestInheritenceA', a:_instanceof(TestInheritenceA))
print('a instanceof TestInheritenceB', a:_instanceof(TestInheritenceB))
print('a instanceof TestInheritenceC', a:_instanceof(TestInheritenceC))

print('b instanceof TestInheritenceA', b:_instanceof(TestInheritenceA))
print('b instanceof TestInheritenceB', b:_instanceof(TestInheritenceB))
print('b instanceof TestInheritenceC', b:_instanceof(TestInheritenceC))

print('c instanceof TestInheritenceA', c:_instanceof(TestInheritenceA))
print('c instanceof TestInheritenceB', c:_instanceof(TestInheritenceB))
print('c instanceof TestInheritenceC', c:_instanceof(TestInheritenceC))
