--[[
This will represent a .class blob of data, to be used with classloaders

Right now I am lazily exploding everything.

But I'm tempted to make all lua class fields into pointers into the data blob,
and give them ffi ctype metatables for reading and writing values.
and then leave the bytecode as-is...

Then again, Java-ASM ClassWriter isn't exactly writing bytes as it goes.
A lot has to be stored and compressed upon conversion to byte array.
I might as well keep it exploded.
--]]
local ffi = require 'ffi'
local table = require 'ext.table'
local assert = require 'ext.assert'
local path = require 'ext.path'
local class = require 'ext.class'

					
-- https://en.wikipedia.org/wiki/List_of_JVM_bytecode_instructions
local instDescForOp = {
	[0x00] = {name='nop'},	-- [No change]	perform no operation
	[0x01] = {name='aconst_null'},	-- → null	push a null reference onto the stack
	[0x02] = {name='iconst_m1'},	-- → -1	load the int value −1 onto the stack
	[0x03] = {name='iconst_0'},	-- → 0	load the int value 0 onto the stack
	[0x04] = {name='iconst_1'},	-- → 1	load the int value 1 onto the stack
	[0x05] = {name='iconst_2'},	-- → 2	load the int value 2 onto the stack
	[0x06] = {name='iconst_3'},	-- → 3	load the int value 3 onto the stack
	[0x07] = {name='iconst_4'},	-- → 4	load the int value 4 onto the stack
	[0x08] = {name='iconst_5'},	-- → 5	load the int value 5 onto the stack
	[0x09] = {name='lconst_0'},	-- → 0L	push 0L (the number zero with type long) onto the stack
	[0x0a] = {name='lconst_1'},	-- → 1L	push 1L (the number one with type long) onto the stack
	[0x0b] = {name='fconst_0'},	-- → 0.0f	push 0.0f on the stack
	[0x0c] = {name='fconst_1'},	-- → 1.0f	push 1.0f on the stack
	[0x0d] = {name='fconst_2'},	-- → 2.0f	push 2.0f on the stack
	[0x0e] = {name='dconst_0'},	-- → 0.0	push the constant 0.0 (a double) onto the stack
	[0x0f] = {name='dconst_1'},	-- → 1.0	push the constant 1.0 (a double) onto the stack
	[0x10] = {name='bipush', args={'uint8_t'}},	-- 1: byte	→ value	push a byte onto the stack as an integer value
	[0x11] = {name='sipush', args={'uint16_t'}},	-- 2: byte1, byte2	→ value	push a short onto the stack as an integer value
	[0x12] = {name='ldc', args={'uint8_t'}},	-- 1: index	→ value	push a constant #index from a constant pool (String, int, float, Class, java.lang.invoke.MethodType, java.lang.invoke.MethodHandle, or a dynamically-computed constant) onto the stack
	[0x13] = {name='ldc_w', args={'uint16_t'}},	-- 2: indexbyte1, indexbyte2	→ value	push a constant #index from a constant pool (String, int, float, Class, java.lang.invoke.MethodType, java.lang.invoke.MethodHandle, or a dynamically-computed constant) onto the stack (wide index is constructed as indexbyte1 << 8 | indexbyte2)
	[0x14] = {name='ldc2_w', args={'uint16_t'}},	-- 2: indexbyte1, indexbyte2	→ value	push a constant #index from a constant pool (double, long, or a dynamically-computed constant) onto the stack (wide index is constructed as indexbyte1 << 8 | indexbyte2)
	[0x15] = {name='iload', args={'uint8_t'}},	-- 1: index	→ value	load an int value from a local variable #index
	[0x16] = {name='lload', args={'uint8_t'}},	-- 1: index	→ value	load a long value from a local variable #index
	[0x17] = {name='fload', args={'uint8_t'}},	-- 1: index	→ value	load a float value from a local variable #index
	[0x18] = {name='dload', args={'uint8_t'}},	-- 1: index	→ value	load a double value from a local variable #index
	[0x19] = {name='aload', args={'uint8_t'}},	-- 1: index	→ objectref	load a reference onto the stack from a local variable #index
	[0x1a] = {name='iload_0'},	-- → value	load an int value from local variable 0
	[0x1b] = {name='iload_1'},	-- → value	load an int value from local variable 1
	[0x1c] = {name='iload_2'},	-- → value	load an int value from local variable 2
	[0x1d] = {name='iload_3'},	-- → value	load an int value from local variable 3
	[0x1e] = {name='lload_0'},	-- → value	load a long value from a local variable 0
	[0x1f] = {name='lload_1'},	-- → value	load a long value from a local variable 1
	[0x20] = {name='lload_2'},	-- → value	load a long value from a local variable 2
	[0x21] = {name='lload_3'},	-- → value	load a long value from a local variable 3
	[0x22] = {name='fload_0'},	-- → value	load a float value from local variable 0
	[0x23] = {name='fload_1'},	-- → value	load a float value from local variable 1
	[0x24] = {name='fload_2'},	-- → value	load a float value from local variable 2
	[0x25] = {name='fload_3'},	-- → value	load a float value from local variable 3
	[0x26] = {name='dload_0'},	-- → value	load a double from local variable 0
	[0x27] = {name='dload_1'},	-- → value	load a double from local variable 1
	[0x28] = {name='dload_2'},	-- → value	load a double from local variable 2
	[0x29] = {name='dload_3'},	-- → value	load a double from local variable 3
	[0x2a] = {name='aload_0'},	-- → objectref	load a reference onto the stack from local variable 0
	[0x2b] = {name='aload_1'},	-- → objectref	load a reference onto the stack from local variable 1
	[0x2c] = {name='aload_2'},	-- → objectref	load a reference onto the stack from local variable 2
	[0x2d] = {name='aload_3'},	-- → objectref	load a reference onto the stack from local variable 3
	[0x2e] = {name='iaload'},	-- arrayref, index → value	load an int from an array
	[0x2f] = {name='laload'},	-- arrayref, index → value	load a long from an array
	[0x30] = {name='faload'},	-- arrayref, index → value	load a float from an array
	[0x31] = {name='daload'},	-- arrayref, index → value	load a double from an array
	[0x32] = {name='aaload'},	-- arrayref, index → value	load onto the stack a reference from an array
	[0x33] = {name='baload'},	-- arrayref, index → value	load a byte or Boolean value from an array
	[0x34] = {name='caload'},	-- arrayref, index → value	load a char from an array
	[0x35] = {name='saload'},	-- arrayref, index → value	load short from array
	[0x36] = {name='istore', args={'uint8_t'}},	-- 1: index	value →	store int value into variable #index
	[0x37] = {name='lstore', args={'uint8_t'}},	-- 1: index	value →	store a long value in a local variable #index
	[0x38] = {name='fstore', args={'uint8_t'}},	-- 1: index	value →	store a float value into a local variable #index
	[0x39] = {name='dstore', args={'uint8_t'}},	-- 1: index	value →	store a double value into a local variable #index
	[0x3a] = {name='astore', args={'uint8_t'}},	-- 1: index	objectref →	store a reference into a local variable #index
	[0x3b] = {name='istore_0'},	-- value →	store int value into variable 0
	[0x3c] = {name='istore_1'},	-- value →	store int value into variable 1
	[0x3d] = {name='istore_2'},	-- value →	store int value into variable 2
	[0x3e] = {name='istore_3'},	-- value →	store int value into variable 3
	[0x3f] = {name='lstore_0'},	-- value →	store a long value in a local variable 0
	[0x40] = {name='lstore_1'},	-- value →	store a long value in a local variable 1
	[0x41] = {name='lstore_2'},	-- value →	store a long value in a local variable 2
	[0x42] = {name='lstore_3'},	-- value →	store a long value in a local variable 3
	[0x43] = {name='fstore_0'},	-- value →	store a float value into local variable 0
	[0x44] = {name='fstore_1'},	-- value →	store a float value into local variable 1
	[0x45] = {name='fstore_2'},	-- value →	store a float value into local variable 2
	[0x46] = {name='fstore_3'},	-- value →	store a float value into local variable 3
	[0x47] = {name='dstore_0'},	-- value →	store a double into local variable 0
	[0x48] = {name='dstore_1'},	-- value →	store a double into local variable 1
	[0x49] = {name='dstore_2'},	-- value →	store a double into local variable 2
	[0x4a] = {name='dstore_3'},	-- value →	store a double into local variable 3
	[0x4b] = {name='astore_0'},	-- objectref →	store a reference into local variable 0
	[0x4c] = {name='astore_1'},	-- objectref →	store a reference into local variable 1
	[0x4d] = {name='astore_2'},	-- objectref →	store a reference into local variable 2
	[0x4e] = {name='astore_3'},	-- objectref →	store a reference into local variable 3
	[0x4f] = {name='iastore'},	-- arrayref, index, value →	store an int into an array
	[0x50] = {name='lastore'},	-- arrayref, index, value →	store a long to an array
	[0x51] = {name='fastore'},	-- arrayref, index, value →	store a float in an array
	[0x52] = {name='dastore'},	-- arrayref, index, value →	store a double into an array
	[0x53] = {name='aastore'},	-- arrayref, index, value →	store a reference in an array
	[0x54] = {name='bastore'},	-- arrayref, index, value →	store a byte or Boolean value into an array
	[0x55] = {name='castore'},	-- arrayref, index, value →	store a char into an array
	[0x56] = {name='sastore'},	-- arrayref, index, value →	store short to array
	[0x57] = {name='pop'},	-- value →	discard the top value on the stack
	[0x58] = {name='pop2'},	-- {value2, value1} →	discard the top two values on the stack (or one value, if it is a double or long)
	[0x59] = {name='dup'},	-- value → value, value	duplicate the value on top of the stack
	[0x5a] = {name='dup_x1'},	-- value2, value1 → value1, value2, value1	insert a copy of the top value into the stack two values from the top. value1 and value2 must not be of the type double or long.
	[0x5b] = {name='dup_x2'},	-- value3, value2, value1 → value1, value3, value2, value1	insert a copy of the top value into the stack two (if value2 is double or long it takes up the entry of value3, too) or three values (if value2 is neither double nor long) from the top
	[0x5c] = {name='dup2'},	-- {value2, value1} → {value2, value1}, {value2, value1}	duplicate top two stack words (two values, if value1 is not double nor long; a single value, if value1 is double or long)
	[0x5d] = {name='dup2_x1'},	-- value3, {value2, value1} → {value2, value1}, value3, {value2, value1}	duplicate two words and insert beneath third word (see explanation above)
	[0x5e] = {name='dup2_x2'},	-- {value4, value3}, {value2, value1} → {value2, value1}, {value4, value3}, {value2, value1}	duplicate two words and insert beneath fourth word
	[0x5f] = {name='swap'},	-- value2, value1 → value1, value2	swaps two top words on the stack (note that value1 and value2 must not be double or long)
	[0x60] = {name='iadd'},	-- value1, value2 → result	add two ints
	[0x61] = {name='ladd'},	-- value1, value2 → result	add two longs
	[0x62] = {name='fadd'},	-- value1, value2 → result	add two floats
	[0x63] = {name='dadd'},	-- value1, value2 → result	add two doubles
	[0x64] = {name='isub'},	-- value1, value2 → result	int subtract
	[0x65] = {name='lsub'},	-- value1, value2 → result	subtract two longs
	[0x66] = {name='fsub'},	-- value1, value2 → result	subtract two floats
	[0x67] = {name='dsub'},	-- value1, value2 → result	subtract a double from another
	[0x68] = {name='imul'},	-- value1, value2 → result	multiply two integers
	[0x69] = {name='lmul'},	-- value1, value2 → result	multiply two longs
	[0x6a] = {name='fmul'},	-- value1, value2 → result	multiply two floats
	[0x6b] = {name='dmul'},	-- value1, value2 → result	multiply two doubles
	[0x6c] = {name='idiv'},	-- value1, value2 → result	divide two integers
	[0x6d] = {name='ldiv'},	-- value1, value2 → result	divide two longs
	[0x6e] = {name='fdiv'},	-- value1, value2 → result	divide two floats
	[0x6f] = {name='ddiv'},	-- value1, value2 → result	divide two doubles
	[0x70] = {name='irem'},	-- value1, value2 → result	logical int remainder
	[0x71] = {name='lrem'},	-- value1, value2 → result	remainder of division of two longs
	[0x72] = {name='frem'},	-- value1, value2 → result	get the remainder from a division between two floats
	[0x73] = {name='drem'},	-- value1, value2 → result	get the remainder from a division between two doubles
	[0x74] = {name='ineg'},	-- value → result	negate int
	[0x75] = {name='lneg'},	-- value → result	negate a long
	[0x76] = {name='fneg'},	-- value → result	negate a float
	[0x77] = {name='dneg'},	-- value → result	negate a double
	[0x78] = {name='ishl'},	-- value1, value2 → result	int shift left
	[0x79] = {name='lshl'},	-- value1, value2 → result	bitwise shift left of a long value1 by int value2 positions
	[0x7a] = {name='ishr'},	-- value1, value2 → result	int arithmetic shift right
	[0x7b] = {name='lshr'},	-- value1, value2 → result	bitwise shift right of a long value1 by int value2 positions
	[0x7c] = {name='iushr'},	-- value1, value2 → result	int logical shift right
	[0x7d] = {name='lushr'},	-- value1, value2 → result	bitwise shift right of a long value1 by int value2 positions, unsigned
	[0x7e] = {name='iand'},	-- value1, value2 → result	perform a bitwise AND on two integers
	[0x7f] = {name='land'},	-- value1, value2 → result	bitwise AND of two longs
	[0x80] = {name='ior'},	-- value1, value2 → result	bitwise int OR
	[0x81] = {name='lor'},	-- value1, value2 → result	bitwise OR of two longs
	[0x82] = {name='ixor'},	-- value1, value2 → result	int xor
	[0x83] = {name='lxor'},	-- value1, value2 → result	bitwise XOR of two longs
	[0x84] = {name='iinc', args={'uint8_t', 'uint8_t'}},	-- 2: index, const	[No change]	increment local variable #index by signed byte const
	[0x85] = {name='i2l'},	-- value → result	convert an int into a long
	[0x86] = {name='i2f'},	-- value → result	convert an int into a float
	[0x87] = {name='i2d'},	-- value → result	convert an int into a double
	[0x88] = {name='l2i'},	-- value → result	convert a long to a int
	[0x89] = {name='l2f'},	-- value → result	convert a long to a float
	[0x8a] = {name='l2d'},	-- value → result	convert a long to a double
	[0x8b] = {name='f2i'},	-- value → result	convert a float to an int
	[0x8c] = {name='f2l'},	-- value → result	convert a float to a long
	[0x8d] = {name='f2d'},	-- value → result	convert a float to a double
	[0x8e] = {name='d2i'},	-- value → result	convert a double to an int
	[0x8f] = {name='d2l'},	-- value → result	convert a double to a long
	[0x90] = {name='d2f'},	-- value → result	convert a double to a float
	[0x91] = {name='i2b'},	-- value → result	convert an int into a byte
	[0x92] = {name='i2c'},	-- value → result	convert an int into a character
	[0x93] = {name='i2s'},	-- value → result	convert an int into a short
	[0x94] = {name='lcmp'},	-- value1, value2 → result	push 0 if the two longs are the same, 1 if value1 is greater than value2, -1 otherwise
	[0x95] = {name='fcmpl'},	-- value1, value2 → result	compare two floats, -1 on NaN
	[0x96] = {name='fcmpg'},	-- value1, value2 → result	compare two floats, 1 on NaN
	[0x97] = {name='dcmpl'},	-- value1, value2 → result	compare two doubles, -1 on NaN
	[0x98] = {name='dcmpg'},	-- value1, value2 → result	compare two doubles, 1 on NaN
	[0x99] = {name='ifeq', args={'uint16_t'}},	-- 2: branchbyte1, branchbyte2	value →	if value is 0, branch to instruction at branchoffset (signed short constructed from unsigned bytes branchbyte1 << 8 | branchbyte2)
	[0x9a] = {name='ifne', args={'uint16_t'}},	-- 2: branchbyte1, branchbyte2	value →	if value is not 0, branch to instruction at branchoffset (signed short constructed from unsigned bytes branchbyte1 << 8 | branchbyte2)
	[0x9b] = {name='iflt', args={'uint16_t'}},	-- 2: branchbyte1, branchbyte2	value →	if value is less than 0, branch to instruction at branchoffset (signed short constructed from unsigned bytes branchbyte1 << 8 | branchbyte2)
	[0x9c] = {name='ifge', args={'uint16_t'}},	-- 2: branchbyte1, branchbyte2	value →	if value is greater than or equal to 0, branch to instruction at branchoffset (signed short constructed from unsigned bytes branchbyte1 << 8 | branchbyte2)
	[0x9d] = {name='ifgt', args={'uint16_t'}},	-- 2: branchbyte1, branchbyte2	value →	if value is greater than 0, branch to instruction at branchoffset (signed short constructed from unsigned bytes branchbyte1 << 8 | branchbyte2)
	[0x9e] = {name='ifle', args={'uint16_t'}},	-- 2: branchbyte1, branchbyte2	value →	if value is less than or equal to 0, branch to instruction at branchoffset (signed short constructed from unsigned bytes branchbyte1 << 8 | branchbyte2)
	[0x9f] = {name='if_icmpeq', args={'uint16_t'}},	-- 2: branchbyte1, branchbyte2	value1, value2 →	if ints are equal, branch to instruction at branchoffset (signed short constructed from unsigned bytes branchbyte1 << 8 | branchbyte2)
	[0xa0] = {name='if_icmpne', args={'uint16_t'}},	-- 2: branchbyte1, branchbyte2	value1, value2 →	if ints are not equal, branch to instruction at branchoffset (signed short constructed from unsigned bytes branchbyte1 << 8 | branchbyte2)
	[0xa1] = {name='if_icmplt', args={'uint16_t'}},	-- 2: branchbyte1, branchbyte2	value1, value2 →	if value1 is less than value2, branch to instruction at branchoffset (signed short constructed from unsigned bytes branchbyte1 << 8 | branchbyte2)
	[0xa2] = {name='if_icmpge', args={'uint16_t'}},	-- 2: branchbyte1, branchbyte2	value1, value2 →	if value1 is greater than or equal to value2, branch to instruction at branchoffset (signed short constructed from unsigned bytes branchbyte1 << 8 | branchbyte2)
	[0xa3] = {name='if_icmpgt', args={'uint16_t'}},	-- 2: branchbyte1, branchbyte2	value1, value2 →	if value1 is greater than value2, branch to instruction at branchoffset (signed short constructed from unsigned bytes branchbyte1 << 8 | branchbyte2)
	[0xa4] = {name='if_icmple', args={'uint16_t'}},	-- 2: branchbyte1, branchbyte2	value1, value2 →	if value1 is less than or equal to value2, branch to instruction at branchoffset (signed short constructed from unsigned bytes branchbyte1 << 8 | branchbyte2)
	[0xa5] = {name='if_acmpeq', args={'uint16_t'}},	-- 2: branchbyte1, branchbyte2	value1, value2 →	if references are equal, branch to instruction at branchoffset (signed short constructed from unsigned bytes branchbyte1 << 8 | branchbyte2)
	[0xa6] = {name='if_acmpne', args={'uint16_t'}},	-- 2: branchbyte1, branchbyte2	value1, value2 →	if references are not equal, branch to instruction at branchoffset (signed short constructed from unsigned bytes branchbyte1 << 8 | branchbyte2)
	[0xa7] = {name='goto', args={'uint16_t'}},	-- 2: branchbyte1, branchbyte2	[no change]	goes to another instruction at branchoffset (signed short constructed from unsigned bytes branchbyte1 << 8 | branchbyte2)
	[0xa8] = {name='jsr', args={'uint16_t'}},	-- 2: branchbyte1, branchbyte2	→ address	jump to subroutine at branchoffset (signed short constructed from unsigned bytes branchbyte1 << 8 | branchbyte2) and place the return address on the stack
	[0xa9] = {name='ret', args={'uint8_t'}},	-- 1: index	[No change]	continue execution from address taken from a local variable #index (the asymmetry with jsr is intentional)
	[0xaa] = {name='tableswitch',
		args = function() error'TODO' end,	--... 
	},	-- 16+: [0–3 bytes padding], defaultbyte1, defaultbyte2, defaultbyte3, defaultbyte4, lowbyte1, lowbyte2, lowbyte3, lowbyte4, highbyte1, highbyte2, highbyte3, highbyte4, jump offsets...	index →	continue execution from an address in the table at offset index
	[0xab] = {name='lookupswitch',
		args = function() error'TODO' end,
	},	-- 8+: <0–3 bytes padding>, defaultbyte1, defaultbyte2, defaultbyte3, defaultbyte4, npairs1, npairs2, npairs3, npairs4, match-offset pairs...	key →	a target address is looked up from a table using a key and execution continues from the instruction at that address
	[0xac] = {name='ireturn'},	-- value → [empty]	return an integer from a method
	[0xad] = {name='lreturn'},	-- value → [empty]	return a long value
	[0xae] = {name='freturn'},	-- value → [empty]	return a float
	[0xaf] = {name='dreturn'},	-- value → [empty]	return a double from a method
	[0xb0] = {name='areturn'},	-- objectref → [empty]	return a reference from a method
	[0xb1] = {name='return'},	-- → [empty]	return from a void method
	[0xb2] = {name='getstatic', args={'uint16_t'}},	-- 2: indexbyte1, indexbyte2	→ value	get a static field value of a class, where the field is identified by field reference in the constant pool index (indexbyte1 << 8 | indexbyte2)
	[0xb3] = {name='putstatic', args={'uint16_t'}},	-- 2: indexbyte1, indexbyte2	value →	set static field to value in a class, where the field is identified by a field reference index in constant pool (indexbyte1 << 8 | indexbyte2)
	[0xb4] = {name='getfield', args={'uint16_t'}},	-- 2: indexbyte1, indexbyte2	objectref → value	get a field value of an object objectref, where the field is identified by field reference in the constant pool index (indexbyte1 << 8 | indexbyte2)
	[0xb5] = {name='putfield', args={'uint16_t'}},	-- 2: indexbyte1, indexbyte2	objectref, value →	set field to value in an object objectref, where the field is identified by a field reference index in constant pool (indexbyte1 << 8 | indexbyte2)
	[0xb6] = {name='invokevirtual', args={'uint16_t'}},	-- 2: indexbyte1, indexbyte2	objectref, [arg1, arg2, ...] → result	invoke virtual method on object objectref and puts the result on the stack (might be void); the method is identified by method reference index in constant pool (indexbyte1 << 8 | indexbyte2)
	[0xb7] = {name='invokespecial', args={'uint16_t'}},	-- 2: indexbyte1, indexbyte2	objectref, [arg1, arg2, ...] → result	invoke instance method on object objectref and puts the result on the stack (might be void); the method is identified by method reference index in constant pool (indexbyte1 << 8 | indexbyte2)
	[0xb8] = {name='invokestatic', args={'uint16_t'}},	-- 2: indexbyte1, indexbyte2	[arg1, arg2, ...] → result	invoke a static method and puts the result on the stack (might be void); the method is identified by method reference index in constant pool (indexbyte1 << 8 | indexbyte2)
	[0xb9] = {name='invokeinterface', args={'uint16_t', 'uint8_t', 'uint8_t'}},	-- 4: indexbyte1, indexbyte2, count, 0	objectref, [arg1, arg2, ...] → result	invokes an interface method on object objectref and puts the result on the stack (might be void); the interface method is identified by method reference index in constant pool (indexbyte1 << 8 | indexbyte2)
	[0xba] = {name='invokedynamic', args={'uint16_t', 'uint8_t', 'uint8_t'}},	-- 4: indexbyte1, indexbyte2, 0, 0	[arg1, arg2, ...] → result	invokes a dynamic method and puts the result on the stack (might be void); the method is identified by method reference index in constant pool (indexbyte1 << 8 | indexbyte2)
	[0xbb] = {name='new', args={'uint16_t'}},	-- 2: indexbyte1, indexbyte2	→ objectref	create new object of type identified by class reference in constant pool index (indexbyte1 << 8 | indexbyte2)
	[0xbc] = {name='newarray', args={'uint8_t'}},	-- 1: atype	count → arrayref	create new array with count elements of primitive type identified by atype
	[0xbd] = {name='anewarray', args={'uint16_t'}},	-- 2: indexbyte1, indexbyte2	count → arrayref	create a new array of references of length count and component type identified by the class reference index (indexbyte1 << 8 | indexbyte2) in the constant pool
	[0xbe] = {name='arraylength'},	-- arrayref → length	get the length of an array
	[0xbf] = {name='athrow'},	-- objectref → [empty], objectref	throws an error or exception (notice that the rest of the stack is cleared, leaving only a reference to the Throwable)
	[0xc0] = {name='checkcast', args={'uint16_t'}},	-- 2: indexbyte1, indexbyte2	objectref → objectref	checks whether an objectref is of a certain type, the class reference of which is in the constant pool at index (indexbyte1 << 8 | indexbyte2)
	[0xc1] = {name='instanceof', args={'uint16_t'}},	-- 2: indexbyte1, indexbyte2	objectref → result	determines if an object objectref is of a given type, identified by class reference index in constant pool (indexbyte1 << 8 | indexbyte2)
	[0xc2] = {name='monitorenter'},	-- objectref →	enter monitor for object ("grab the lock" – start of synchronized() section)
	[0xc3] = {name='monitorexit'},	-- objectref →	exit monitor for object ("release the lock" – end of synchronized() section)
	[0xc4] = {name='wide', args=function() error'TODO' end},	-- 3/5: opcode, indexbyte1, indexbyte2 or iinc, indexbyte1, indexbyte2, countbyte1, countbyte2	[same as for corresponding instructions]	execute opcode, where opcode is either iload, fload, aload, lload, dload, istore, fstore, astore, lstore, dstore, or ret, but assume the index is 16 bit; or execute iinc, where the index is 16 bits and the constant to increment by is a signed 16 bit short
	[0xc5] = {name='multianewarray', args={'uint16_t', 'uint8_t'}},	-- 3: indexbyte1, indexbyte2, dimensions	count1, [count2,...] → arrayref	create a new array of dimensions dimensions of type identified by class reference in constant pool index (indexbyte1 << 8 | indexbyte2); the sizes of each dimension is identified by count1, [count2, etc.]
	[0xc6] = {name='ifnull', args={'uint16_t'}},	-- 2: branchbyte1, branchbyte2	value →	if value is null, branch to instruction at branchoffset (signed short constructed from unsigned bytes branchbyte1 << 8 | branchbyte2)
	[0xc7] = {name='ifnonnull', args={'uint16_t'}},	-- 2: branchbyte1, branchbyte2	value →	if value is not null, branch to instruction at branchoffset (signed short constructed from unsigned bytes branchbyte1 << 8 | branchbyte2)
	[0xc8] = {name='goto_w', args={'uint32_t'}},	-- 4: branchbyte1, branchbyte2, branchbyte3, branchbyte4	[no change]	goes to another instruction at branchoffset (signed int constructed from unsigned bytes branchbyte1 << 24 | branchbyte2 << 16 | branchbyte3 << 8 | branchbyte4)
	[0xc9] = {name='jsr_w', args={'uint32_t'}},	-- 4: branchbyte1, branchbyte2, branchbyte3, branchbyte4	→ address	jump to subroutine at branchoffset (signed int constructed from unsigned bytes branchbyte1 << 24 | branchbyte2 << 16 | branchbyte3 << 8 | branchbyte4) and place the return address on the stack
	[0xca] = {name='breakpoint'},	-- reserved for breakpoints in Java debuggers; should not appear in any class file
	[0xfe] = {name='impdep1'},	-- reserved for implementation-dependent operations within debuggers; should not appear in any class file
	[0xff] = {name='impdep2'},	-- reserved for implementation-dependent operations within debuggers; should not appear in any class file
	--(no name)	cb-fd				these values are currently unassigned for opcodes and are reserved for future use
}


local JavaClassData = class()
JavaClassData.__name = 'JavaClassData' 

function JavaClassData:init(data)
	if type(args) == 'string' then
		self:readData(args)	-- assume its raw data 
	end
end

-- static ctor
function JavaClassData:fromFile(filename)
	local o = JavaClassData()
	o:readData((assert(path(filename):read())))
	return o
end

local Blob = class()
function Blob:init(data)
	self.data = assert.type(data, 'string')
	self.len = #self.data
	self.ptr = ffi.cast('uint8_t*', self.data)
	self.ofs = 0
end
function Blob:read(ctype)
	local size = ffi.sizeof(ctype)
	if size + self.ofs > self.len then
		error("read past the end")
	end

	local result
	if ffi.abi'be' then
		result = ffi.cast(ffi.typeof('$*', ctype), self.ptr + self.ofs)[0]
	else -- if ffi.abi'le' then
		local tmp = ffi.typeof('$[1]', ffi.typeof(ctype))()
		local tmpb = ffi.cast('uint8_t*', tmp)
		for i=0,ffi.sizeof(ctype)-1 do
			tmpb[i] = self.ptr[self.ofs + ffi.sizeof(ctype)-1-i]
		end
		result = tmp[0]
	end
	self.ofs = self.ofs + size
	return result
end
function Blob:readString(size)
	if size + self.ofs > self.len then
		error("read past the end")
	end
	local result = ffi.string(self.ptr + self.ofs, size)
	self.ofs = self.ofs + size
	return result
end
function Blob:readBlob(size)
	return Blob(self:readString(size))
end
function Blob:readu1() return self:read'uint8_t' end
function Blob:readu2() return self:read'uint16_t' end
function Blob:readu4() return self:read'uint32_t' end
function Blob:done() return self.ofs == self.len end
function Blob:assertDone()
	if self.ofs < self.len then
		error('still have '..(self.len-self.ofs)..' bytes remaining')
	end
end

function JavaClassData:readData(data)
	local function deepCopy(t)
		if type(t) ~= 'table' then return t end
		local t2 = table(t)
		for k,v in pairs(t) do
			t2[k] = deepCopy(v)
		end
		return t2
	end

	local function deepCopyIndex(index)
		return deepCopy(assert.index(self.constants, index))
	end

	-- this uses deepCopyIndex but does so only after self.constants is deep-copied
	local function readAttrs(b)
		local attrCount = b:readu2()
		if attrCount == 0 then return end
		local attrs = table()
		for i=0,attrCount-1 do
			local attr = {}
			attr.name = deepCopyIndex(b:readu2())	-- index into constants[]
			local length = b:readu4()
			attr.data = b:readString(length)
			attrs:insert(attr)
		end
		return attrs
	end

	local blob = Blob(data)
	local magic = blob:readu4()
	assert.eq(magic, 0xcafebabe)
	local minorVersion = blob:readu2()
	local majorVersion = blob:readu2()
	-- store version info or nah?
	local constantCount = blob:readu2()
	self.constants = table()
	do
		local skipnext
		for i=1,constantCount-1 do
			if not skipnext then
				local tag = blob:read'uint8_t'
				local constant = {index=i, tag=tag}
				if tag == 7 then		-- class
					constant.tag = 'class'
					constant.nameIndex = blob:readu2()
				elseif tag == 9 then		-- fieldref
					constant.tag = 'fieldRef'
					constant.classIndex = blob:readu2()
					constant.nameAndTypeIndex = blob:readu2()
				elseif tag == 10 then			-- methodref
					constant.tag = 'methodRef'
					constant.classIndex = blob:readu2()
					constant.nameAndTypeIndex = blob:readu2()
				elseif tag == 11 then 			-- interfaceMethodRef
					constant.tag = 'interfaceMethodRef'
					constant.classIndex = blob:readu2()
					constant.nameAndTypeIndex = blob:readu2()
				elseif tag == 8 then	-- string ... string literal
					constant.tag = 'string'
					constant.stringIndex = blob:readu2()
				elseif tag == 3 then	-- integer
					constant.tag = 'int'
					constant.value = blob:read'int32_t'
				elseif tag == 4 then	-- float
					constant.tag = 'float'
					constant.value = blob:read'float'
				elseif tag == 5 then	-- long
					constant.tag = 'long'
					constant.value = blob:read'int64_t'
					-- "all 8-byte constants take up 2 entries in the constant pool ..." wrt their data only, right? no extra tag in there right?
					skipnext = true
				elseif tag == 6 then	-- double
					constant.tag = 'double'
					constant.value = blob:read'double'
					skipnext = true
				elseif tag == 12 then	-- nameAndType
					constant.tag = 'nameAndType'
					constant.nameIndex = blob:readu2()
					constant.descriptorIndex = blob:readu2()
				elseif tag == 1 then 	-- utf8string ... the string data
					local length = blob:readu2()
					--[[ keep a table?
					constant.tag = 'utf8string'
					constant.value = blob:readString(length)
					--]]
					-- [[ or nah?
					constant = blob:readString(length)
					--]]
				elseif tag == 15 then	-- methodHandle
					constant.tag = 'methodHandle'
					constant.referenceKind = blob:readu2()
					constant.referenceIndex = blob:readu2()
				elseif tag == 16 then	-- methodType
					constant.tag = 'methodType'
					constant.descriptorIndex = blob:readu2()
				elseif tag == 18 then	-- invokeDynamic
					constant.tag = 'invokeDynamic'
					constant.boostrapMethodAttrIndex = blob:readu2()
					constant.nameAndTypeIndex = blob:readu2()
				elseif tag == 19 then	-- module
					constant.tag = 'module'
					constant.nameIndex = blob:readu2()
				elseif tag == 20 then	-- package
					constant.tag = 'package'
					constant.nameIndex = blob:readu2()
				else
					error('unknown tag '..tostring(tag)..' / 0x'..bit.tohex(tag, 2)
						..' at offset 0x'..bit.tohex(ofs)
					)
				end
				self.constants:insert(constant)
			else
				self.constants:insert(false)
				skipnext = false
			end
		end
	end
	-- are all constants only self-referencing?
	-- or do any reference outside into fields or methods?
	-- but the reference order is not always increasing,
	--  so I'll have to process it afterwards
	-- there's no recursive references, right?
	for _,constant in ipairs(self.constants) do
		if type(constant) == 'table' then 	-- skip fillers for double and long
			constant.index = nil
			-- TODO TODO also assert matching type?
			if constant.nameIndex then
				constant.name = assert.index(self.constants, constant.nameIndex)
				constant.nameIndex = nil
			end
			if constant.classIndex then
				constant.class = assert.index(self.constants, constant.classIndex)
				constant.classIndex = nil
			end
			if constant.nameAndTypeIndex then
				constant.nameAndType = assert.index(self.constants, constant.nameAndTypeIndex)
				constant.nameAndTypeIndex = nil
			end
			if constant.stringIndex then
				constant.string = assert.index(self.constants, constant.stringIndex)
				constant.stringIndex = nil
			end
			if constant.descriptorIndex then
				constant.descriptor = assert.index(self.constants, constant.descriptorIndex)
				constant.descriptorIndex = nil
			end
			if constant.referenceIndex then
				constant.reference = assert.index(self.constants, constant.referenceIndex)
				constant.referenceIndex = nil
			-- maybe this is to the attrs[] list?
			end
			if constant.bootstrapMethodAttrIndex then
				constant.bootstrapMethodAttr = assert.index(self.constants, constant.bootstrapMethodAttrIndex)
				constant.bootstrapMethodAttrIndex = nil
			end
		end
	end

	-- only after constants refs are set, now deep copy
	-- (since constants has out-of-order refs)
	self.constants = deepCopy(self.constants)

	self.accessFlags = blob:readu2()
	self.thisClass = deepCopyIndex(blob:readu2())
	self.superClass = deepCopyIndex(blob:readu2())

	local interfaceCount = blob:readu2()
	if interfaceCount > 0 then
		self.interfaces = table()
		for i=0,interfaceCount-1 do
			local interface = deepCopyIndex(blob:readu2())
			self.interfaces:insert(interface)
		end
	end

	local fieldCount = blob:readu2()
	self.fields = table()
	for i=0,fieldCount-1 do
		local field = {}
		field.accessFlags = blob:readu2()

		field.name = deepCopyIndex(blob:readu2())
		field.descriptor = deepCopyIndex(blob:readu2())

		local attrs = readAttrs(blob)
		if attrs then
			assert.len(attrs, 1)
			local attr = attrs[1]
			field.attrName = attr.name
			assert.len(attr.data, 2)
			local attrblob = Blob(attr.data)
			field.constantValue = attrblob:readu2()
			attrblob:assertDone()
		end
		self.fields:insert(field)
	end

	local methodCount = blob:readu2()
	self.methods = table()
	for i=0,methodCount-1 do
		local method = {}
		method.accessFlags = blob:readu2()
		
		method.name = deepCopyIndex(blob:readu2())
		method.descriptor = deepCopyIndex(blob:readu2())
	
		-- method attribute #1 = code attribute
		local attrs = readAttrs(blob)
		if attrs then
			assert.len(attrs, 1)
			local codeAttr = attrs[1]

			local code = {}
			code.name = codeAttr.name

			local cblob = Blob(codeAttr.data)
			code.maxStack = cblob:readu2()
			code.maxLocals = cblob:readu2()
			
			local codeLength = cblob:readu4()
			local insns = cblob:readString(codeLength)
			
			-- [[
			do
				local insBlob = Blob(insns)
				code.insts = table()
				while not insBlob:done() do
					local op = insBlob:readu1()
					local instDesc = assert.index(instDescForOp, op)
					local inst = table()
					inst:insert((assert.index(instDesc, 'name')))
					local argDesc = instDesc.arg
					if argDesc then
						if type(argDesc) == 'table' then
							for _,ctype in ipairs(argDesc) do
								inst:insert((insBlob:read(ctype)))
							end
						elseif type(argDesc) == 'function' then
							print'WARNING THIS ISNT IMPLEMENTED YET'
						else
							error'here'
						end
					end
					code.insts:insert(inst)
				end
				insBlob:assertDone()
			end
			--]]
			
			local exceptionCount = cblob:readu2()
			if exceptionCount > 0 then
				code.exceptions = table()
				for i=0,exceptionCount-1 do
					local ex = {}
					ex.startPC = cblob:readu2()
					ex.endPC = cblob:readu2()
					ex.handlerPC = cblob:readu2()
					ex.catchType = cblob:readu2()
					code.exceptions:insert(ex)
				end
			end

			-- code attribute #1 = stack map attribute
			local codeAttrs = readAttrs(cblob)
			if codeAttrs then
				assert.len(codeAttrs, 1)
				local smAttr = codeAttrs[1]
				local stackmap = {}
				stackmap.name = smAttr.name

				--[[
				local smBlob = Blob(smAttr.data)
				local numEntries = smBlob:readu2()
print('numEntries', numEntries)				
				stackmap.entries = {}
				for i=1,numEntries do
					local smFrame = {}

					local function readVerificationTypeInfo()
						local typeinfo = {}
						typeinfo.tag = smBlob:readu1()
						if tag == 0 then -- top
						elseif tag == 1 then -- integer
						elseif tag == 2 then -- float
						elseif tag == 5 then -- null
						elseif tag == 6 then -- uninitialized 'this'
						elseif tag == 7 then -- object
						elseif tag == 7 then	-- object
							typeinfo.value = deepCopyIndex(smBlob:readu2())
						elseif tag == 8 then	-- uninitialized
							typeinfo.offset = smBlob:readu2()
						
						elseif tag == 4	-- long 
						or tag == 5		-- double 
						then
							-- for double and long:
							-- "requires two locations in the local varaibles array"
							-- ... does that mean we skip 2 here as well? 
							-- wait am I supposed to be reading the u2 that the others use as well?
							-- but it's long and double ... do I read u4? that's not in specs.
							-- do I just skip the next u1 tag? weird.
							--smBlob:readu1()
							--smBlob:readu2()
							--smBlob:readu4()
						else
							error("unknown verification type tag "..tostring(tag))
						end
						return typeinfo
					end

					local frameType = smBlob:readu1()
print('reading entry', frameType)					
					smFrame.type = frameType
					if frameType < 64 then
						-- "same"
					elseif frameType < 128 then
						-- "locals 1 stack item"
						smFrame.stack = readVerificationTypeInfo()
					elseif frameType < 247 then
						-- 128-247 = reserved
print('found reseved stack map frame type', frameType)
					elseif frameType == 247 then
						-- "locals 1 stack item extended"
						smFrame.stack = readVerificationTypeInfo()
					elseif frameType < 251 then
						-- "chop frame"
						smFrame.offsetDelta = smBlob:readu2()
					elseif frameType == 251 then
						-- "same frame extended"
						smFrame.offsetDelta = smBlob:readu2()
					elseif frameType < 255 then
						-- "append"
						smFrame.offsetDelta = smBlob:readu2()
						local numLocals = frameType - 251
						if numLocals > 0 then
							smFrame.locals = {}
							for i=1,numLocals do
								smFrame.locals[i] = readVerificationTypeInfo()
							end
						end
					else
						assert.eq(frameType, 255)
						-- "full frame"
						smFrame.offsetDelta = smBlob:readu2()
						local numLocals = smBlob:readu2()
						if numLocals > 0 then
							smFrame.locals = {}
							for i=1,numLocals do
								smFrame.locals[i] = readVerificationTypeInfo()
							end
						end
						local numStackItems = smBlob:readu2()
						if numStackItems > 0 then
							smFrame.stackItems = {}
							for i=1,numStackItems do
								smFrame.stackItems[i] = readVerificationTypeInfo()
							end
						end
					end

					stackmap.entries[i] = smFrame
				end
				smBlob:assertDone()
				--]]
				code.stackmap = stackmap
			end

			cblob:assertDone()
			method.code = code
		end
		self.methods:insert(method)
	end

	self.attrs = readAttrs(blob)

	blob:assertDone()
end

return JavaClassData
