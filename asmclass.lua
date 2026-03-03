--[[
This will represent a .class blob of data, to be used with classloaders

Right now I am lazily exploding everything.

But I'm tempted to make all lua class fields into pointers into the data blob,
and give them ffi ctype metatables for reading and writing values.
and then leave the bytecode as-is...

Then again, Java-ASM ClassWriter isn't exactly writing bytes as it goes.
A lot has to be stored and compressed upon conversion to byte array.
I might as well keep it exploded.

...
Every classname is slash-separated and every signature will be the JNI style.
If I translated them then I'd have to translate to and from the compiled bytecode, which is too much.

My best attempt at interpreting. ..
https://docs.oracle.com/javase/specs/jvms/se10/html/jvms-4.html
https://en.wikipedia.org/wiki/List_of_JVM_bytecode_instructions
--]]
local ffi = require 'ffi'
local table = require 'ext.table'
local assert = require 'ext.assert'
local string = require 'ext.string'
local path = require 'ext.path'
local class = require 'ext.class'
local ReadBlob = require 'java.blob'.ReadBlob
local WriteBlob = require 'java.blob'.WriteBlob
local castToNumberOrJPrim = require 'java.blob'.castToNumberOrJPrim
local classAccessFlags = require 'java.util'.classAccessFlags
local nestedClassAccessFlags = require 'java.util'.nestedClassAccessFlags
local fieldAccessFlags = require 'java.util'.fieldAccessFlags
local methodAccessFlags = require 'java.util'.methodAccessFlags
local setFlagsToObj = require 'java.util'.setFlagsToObj
local getFlagsFromObj = require 'java.util'.getFlagsFromObj
local sigStrToObj = require 'java.util'.sigStrToObj

local function deepCopy(t)
	if type(t) ~= 'table' then return t end
	local t2 = table(t)
	for k,v in pairs(t) do
		t2[k] = deepCopy(v)
	end
	return t2
end

-- I'd write these as member methods, but I don't want to write the instruction table as a member so ...
local function readClassName(asmClass, index)
	local const = assert.index(asmClass.constants, index, 'asmClass.constants')
	assert.type(const, 'table', 'const class type')
	assert.eq(const.tag, 'class', 'const class tag')
	return assert.type(const.name, 'string')
end

local function instPushClass(inst, insBlob, asmClass)
	inst:insert((readClassName(asmClass, insBlob:readu2())))
end
local function insPopClass(inst, index, asmClass)
	return asmClass.addConst{
		tag = 'class',
		name = inst[index],
	}, index+1
end

local function instPushMethod(inst, insBlob, asmClass)
	local methodIndex = insBlob:readu2()
	local method = assert.index(asmClass.constants, methodIndex)
	assert.eq(method.tag, 'methodRef')
	inst:insert(method.class.name)
	inst:insert(method.nameAndType.name)
	inst:insert(method.nameAndType.sig)
end
local function instPopMethod(inst, index, asmClass)
	local methodIndex = asmClass.addConst{
		tag = 'methodRef',
		class = {
			tag = 'class',
			name = inst[index],
		},
		nameAndType = {
			tag = 'nameAndType',
			name = inst[index+1],
			sig = inst[index+2],
		},
	}
-- this now encodes it as a blob, so equality testing will be faster
--assert.eq('methodRef', assert.index(assert.index(asmClass.constants, methodIndex), 'tag'))
	return methodIndex, index+3
end

local function instPushField(inst, insBlob, asmClass)
	local fieldIndex = insBlob:readu2()
	local field = assert.index(asmClass.constants, fieldIndex)
	assert.eq(field.tag, 'fieldRef')
	inst:insert(field.class.name)
	inst:insert(field.nameAndType.name)
	inst:insert(field.nameAndType.sig)
end
local function instPopField(inst, index, asmClass)
	local fieldIndex = asmClass.addConst{
		tag = 'fieldRef',
		class = {
			tag = 'class',
			name = inst[index],
		},
		nameAndType = {
			tag = 'nameAndType',
			name = inst[index+1],
			sig = inst[index+2],
		},
	}
-- this now encodes it as a blob, so equality testing will be faster
--assert.eq('fieldRef', assert.index(assert.index(asmClass.constants, fieldIndex), 'tag'))
	return fieldIndex, index+3
end

local function instPushConst(inst, insBlob, asmClass, constIndex)
	local const = asmClass.constants[constIndex]
	if not const then
		-- how do we notice 'dynamic index' ?
		inst:insert(constIndex)
	else
		-- value type ...
		if const.tag == 'class' then
			inst:insert(const.tag)
			inst:insert(const.name)
		elseif const.tag == 'methodHandle' then
			inst:insert(const.tag)
			inst:insert(const.refKind)
			inst:insert(const.reference)
		elseif const.tag == 'methodType' then
			inst:insert(const.tag)
			inst:insert(const.sig)
		elseif const.tag == 'int'
		or const.tag == 'float'
		then
			-- if it's a number then leave a hint at what kind of number
			-- or how about for floats, use a dot ...
			inst:insert(const.tag)
			inst:insert(const.value)
		elseif const.tag == 'string' then
			inst:insert(const.tag)
			inst:insert(const.value)
		else
			error('instPushConst with unsupported tag '..const.tag)
		end
	end
end
local function instPopConst(inst, index, asmClass)
	local tag = inst[index] index=index+1
	if type(tag) == 'number' then
		return tag, index
	elseif tag == 'class' then
		return asmClass.addConst{
			tag = tag,
			name = inst[index],
		}, index+1
	elseif tag == 'methodHandle' then
		return asmClass.addConst{
			tag = tag,
			refKind = inst[index],
			reference = inst[index+1],
		}, index+2
	elseif tag == 'methodType' then
		return asmClass.addConst{
			tag = tag,
			sig = inst[index],
		}, index+1
	elseif tag == 'float' or tag == 'int' then
		return asmClass.addConst{
			tag = tag,
			value = inst[index],
		}, index+1
	elseif tag == 'string' then
		return asmClass.addConst{
			tag = tag,
			value = inst[index],
		}, index+1
	else
		error('instPopConst with unsupported tag '..tag)
	end
end

local function instPushConst2(inst, insBlob, asmClass, constIndex)
	local const = asmClass.constants[constIndex]
	if not const then
		-- how do we notice 'dynamic index' ?
		inst:insert(constIndex)
	else
		if const.tag == 'long' then
			inst:insert(const.tag)
			inst:insert(const.value)
			--inst:insert(ffi.cast('int64_t', const.value))	-- forc LL suffix
		elseif const.tag == 'double' then
			inst:insert(const.tag)
			inst:insert(const.value)	-- forcing serialization to use a dot would be nice ...
		else
			error('instPushConst2 with unsupported tag '..const.tag)
		end
	end
end
local function instPopConst2(inst, index, asmClass)
	local tag = inst[index] index=index+1
	if type(tag) == 'number' then
		return tag, index
	elseif tag == 'long' or tag == 'double' then
		local value = assert.index(inst, index)
		value = castToNumberOrJPrim(value)
		return asmClass.addConst{
			tag = tag,
			value = value,
		}, index+1
	else
		error('instPopConst2 with unsupported tag '..tag)
	end
end


local instDescForOp = {
	[0x00] = {name='nop'},	-- [No change] .... perform no operation
	[0x01] = {name='aconst_null', stackadd=1},	-- → null .... push a null reference onto the stack
	[0x02] = {name='iconst_m1', stackadd=1},	-- → -1 .... load the int value −1 onto the stack
	[0x03] = {name='iconst_0', stackadd=1},	-- → 0 .... load the int value 0 onto the stack
	[0x04] = {name='iconst_1', stackadd=1},	-- → 1 .... load the int value 1 onto the stack
	[0x05] = {name='iconst_2', stackadd=1},	-- → 2 .... load the int value 2 onto the stack
	[0x06] = {name='iconst_3', stackadd=1},	-- → 3 .... load the int value 3 onto the stack
	[0x07] = {name='iconst_4', stackadd=1},	-- → 4 .... load the int value 4 onto the stack
	[0x08] = {name='iconst_5', stackadd=1},	-- → 5 .... load the int value 5 onto the stack
	[0x09] = {name='lconst_0', stackadd=2},	-- → 0L .... push 0L (the number zero with type long) onto the stack
	[0x0a] = {name='lconst_1', stackadd=2},	-- → 1L .... push 1L (the number one with type long) onto the stack
	[0x0b] = {name='fconst_0', stackadd=1},	-- → 0.0f .... push 0.0f on the stack
	[0x0c] = {name='fconst_1', stackadd=1},	-- → 1.0f .... push 1.0f on the stack
	[0x0d] = {name='fconst_2', stackadd=1},	-- → 2.0f .... push 2.0f on the stack
	[0x0e] = {name='dconst_0', stackadd=2},	-- → 0.0 .... push the constant 0.0 (a double) onto the stack
	[0x0f] = {name='dconst_1', stackadd=2},	-- → 1.0 .... push the constant 1.0 (a double) onto the stack
	[0x10] = {name='bipush', args={'uint8_t'}, stackadd=1},	-- 1: byte .... → value .... push a byte onto the stack as an integer value
	[0x11] = {name='sipush', args={'uint16_t'}, stackadd=1},	-- 2: byte1, byte2 .... → value .... push a short onto the stack as an integer value

	-- 1: index .... → value .... push a constant #index from a constant pool (String, int, float, Class, java.lang.invoke.MethodType, java.lang.invoke.MethodHandle, or a dynamically-computed constant) onto the stack
	[0x12] = {
		name='ldc',
		--args={'uint8_t'}, .... -- TODO is it worth it to lookup the constants[] table if the arg could be dynamically-computed constant?
		stackadd=1,
		args = function(inst, insBlob, asmClass)
			instPushConst(inst, insBlob, asmClass, insBlob:readu1())
		end,
		write = function(inst, insBlob, asmClass)
			insBlob:writeu1(instPopConst(inst, 2, asmClass))
		end,
	},

	-- 2: indexbyte1, indexbyte2 .... → value .... push a constant #index from a constant pool (String, int, float, Class, java.lang.invoke.MethodType, java.lang.invoke.MethodHandle, or a dynamically-computed constant) onto the stack (wide index is constructed as indexbyte1 << 8 | indexbyte2)
	[0x13] = {
		name='ldc_w',
		--args={'uint16_t'},
		stackadd=1,
		args = function(inst, insBlob, asmClass)
			instPushConst(inst, insBlob, asmClass, insBlob:readu2())
		end,
		write = function(inst, insBlob, asmClass)
			insBlob:writeu2(instPopConst(inst, 2, asmClass))
		end,
	},

	-- 2: indexbyte1, indexbyte2 .... → value .... push a constant #index from a constant pool (double, long, or a dynamically-computed constant) onto the stack (wide index is constructed as indexbyte1 << 8 | indexbyte2)
	[0x14] = {
		name='ldc2_w',
		--args={'uint16_t'},
		stackadd=2,
		args = function(inst, insBlob, asmClass)
			instPushConst2(inst, insBlob, asmClass, insBlob:readu2())
		end,
		write = function(inst, insBlob, asmClass)
			insBlob:writeu2(instPopConst2(inst, 2, asmClass))
		end,
	},

	-- 1: index .... → value .... load an int value from a local variable #index
	[0x15] = {
		name='iload',
		args={'uint8_t'},
		stackadd=1,
		maxLocals = function(inst)
			return assert(tonumber(inst[2])) + 1
		end,
	},

	-- 1: index .... → value .... load a long value from a local variable #index
	[0x16] = {
		name='lload',
		args={'uint8_t'},
		stackadd=2,
		maxLocals = function(inst)
			return assert(tonumber(inst[2])) + 2
		end,
	},

	-- 1: index .... → value .... load a float value from a local variable #index
	[0x17] = {
		name='fload',
		args={'uint8_t'},
		stackadd=1,
		maxLocals = function(inst)
			return assert(tonumber(inst[2])) + 1
		end,
	},

	-- 1: index .... → value .... load a double value from a local variable #index
	[0x18] = {
		name='dload',
		args={'uint8_t'},
		stackadd=2,
		maxLocals = function(inst)
			return assert(tonumber(inst[2])) + 2
		end,
	},

	-- 1: index .... → objectref .... load a reference onto the stack from a local variable #index
	[0x19] = {
		name='aload',
		args={'uint8_t'},
		stackadd=1,
		maxLocals = function(inst)
			return assert(tonumber(inst[2])) + 1
		end,
	},

	[0x1a] = {name='iload_0', stackadd=1, maxLocals=1},	-- → value .... load an int value from local variable 0
	[0x1b] = {name='iload_1', stackadd=1, maxLocals=2},	-- → value .... load an int value from local variable 1
	[0x1c] = {name='iload_2', stackadd=1, maxLocals=3},	-- → value .... load an int value from local variable 2
	[0x1d] = {name='iload_3', stackadd=1, maxLocals=4},	-- → value .... load an int value from local variable 3
	[0x1e] = {name='lload_0', stackadd=2, maxLocals=2},	-- → value .... load a long value from a local variable 0
	[0x1f] = {name='lload_1', stackadd=2, maxLocals=3},	-- → value .... load a long value from a local variable 1
	[0x20] = {name='lload_2', stackadd=2, maxLocals=4},	-- → value .... load a long value from a local variable 2
	[0x21] = {name='lload_3', stackadd=2, maxLocals=5},	-- → value .... load a long value from a local variable 3
	[0x22] = {name='fload_0', stackadd=1, maxLocals=1},	-- → value .... load a float value from local variable 0
	[0x23] = {name='fload_1', stackadd=1, maxLocals=2},	-- → value .... load a float value from local variable 1
	[0x24] = {name='fload_2', stackadd=1, maxLocals=3},	-- → value .... load a float value from local variable 2
	[0x25] = {name='fload_3', stackadd=1, maxLocals=4},	-- → value .... load a float value from local variable 3
	[0x26] = {name='dload_0', stackadd=2, maxLocals=2},	-- → value .... load a double from local variable 0
	[0x27] = {name='dload_1', stackadd=2, maxLocals=3},	-- → value .... load a double from local variable 1
	[0x28] = {name='dload_2', stackadd=2, maxLocals=4},	-- → value .... load a double from local variable 2
	[0x29] = {name='dload_3', stackadd=2, maxLocals=5},	-- → value .... load a double from local variable 3
	[0x2a] = {name='aload_0', stackadd=1, maxLocals=1},	-- → objectref .... load a reference onto the stack from local variable 0
	[0x2b] = {name='aload_1', stackadd=1, maxLocals=2},	-- → objectref .... load a reference onto the stack from local variable 1
	[0x2c] = {name='aload_2', stackadd=1, maxLocals=3},	-- → objectref .... load a reference onto the stack from local variable 2
	[0x2d] = {name='aload_3', stackadd=1, maxLocals=4},	-- → objectref .... load a reference onto the stack from local variable 3
	[0x2e] = {name='iaload', stackadd=1, stacksub=2},	-- arrayref, index → value .... load an int from an array
	[0x2f] = {name='laload', stackadd=2, stacksub=2},	-- arrayref, index → value .... load a long from an array
	[0x30] = {name='faload', stackadd=1, stacksub=2},	-- arrayref, index → value .... load a float from an array
	[0x31] = {name='daload', stackadd=2, stacksub=2},	-- arrayref, index → value .... load a double from an array
	[0x32] = {name='aaload', stackadd=1, stacksub=2},	-- arrayref, index → value .... load onto the stack a reference from an array
	[0x33] = {name='baload', stackadd=1, stacksub=2},	-- arrayref, index → value .... load a byte or Boolean value from an array
	[0x34] = {name='caload', stackadd=1, stacksub=2},	-- arrayref, index → value .... load a char from an array
	[0x35] = {name='saload', stackadd=1, stacksub=2},	-- arrayref, index → value .... load short from array

	-- 1: index .... value → .... store int value into variable #index
	-- TODO in some cases where the previous instruction is a pushed int, the maxLocals from this can be deterministic...
	[0x36] = {
		name='istore',
		args={'uint8_t'},
		stacksub=1,
		maxLocals = function(inst)
			-- istore $localIndex
			local localIndex = assert(tonumber(inst[2]))
			return localIndex + 1
		end,
	},

	-- 1: index .... value → .... store a long value in a local variable #index
	[0x37] = {
		name='lstore',
		args={'uint8_t'},
		stacksub=2,
		maxLocals = function(inst)
			-- lstore $localIndex
			local localIndex = assert(tonumber(inst[2]))
			return localIndex + 2
		end,
	},

	-- 1: index .... value → .... store a float value into a local variable #index
	[0x38] = {
		name='fstore',
		args={'uint8_t'},
		stacksub=1,
		maxLocals = function(inst)
			-- fstore $localIndex
			local localIndex = assert(tonumber(inst[2]))
			return localIndex + 1
		end,
	},

	-- 1: index .... value → .... store a double value into a local variable #index
	[0x39] = {
		name='dstore',
		args={'uint8_t'},
		stacksub=2,
		maxLocals = function(inst)
			-- dstore $localIndex
			local localIndex = assert(tonumber(inst[2]))
			return localIndex + 2
		end,
	},

	-- 1: index .... objectref → .... store a reference into a local variable #index
	[0x3a] = {
		name='astore',
		args={'uint8_t'},
		stacksub=1,
		maxLocals = function(inst)
			-- astore $localIndex
			local localIndex = assert(tonumber(inst[2]))
			return localIndex + 1
		end,
	},

	[0x3b] = {name='istore_0', stacksub=1, maxLocals=1},	-- value → .... store int value into variable 0
	[0x3c] = {name='istore_1', stacksub=1, maxLocals=2},	-- value → .... store int value into variable 1
	[0x3d] = {name='istore_2', stacksub=1, maxLocals=3},	-- value → .... store int value into variable 2
	[0x3e] = {name='istore_3', stacksub=1, maxLocals=4},	-- value → .... store int value into variable 3
	[0x3f] = {name='lstore_0', stacksub=2, maxLocals=2},	-- value → .... store a long value in a local variable 0
	[0x40] = {name='lstore_1', stacksub=2, maxLocals=3},	-- value → .... store a long value in a local variable 1
	[0x41] = {name='lstore_2', stacksub=2, maxLocals=4},	-- value → .... store a long value in a local variable 2
	[0x42] = {name='lstore_3', stacksub=2, maxLocals=5},	-- value → .... store a long value in a local variable 3
	[0x43] = {name='fstore_0', stacksub=1, maxLocals=1},	-- value → .... store a float value into local variable 0
	[0x44] = {name='fstore_1', stacksub=1, maxLocals=2},	-- value → .... store a float value into local variable 1
	[0x45] = {name='fstore_2', stacksub=1, maxLocals=3},	-- value → .... store a float value into local variable 2
	[0x46] = {name='fstore_3', stacksub=1, maxLocals=4},	-- value → .... store a float value into local variable 3
	[0x47] = {name='dstore_0', stacksub=2, maxLocals=2},	-- value → .... store a double into local variable 0
	[0x48] = {name='dstore_1', stacksub=2, maxLocals=3},	-- value → .... store a double into local variable 1
	[0x49] = {name='dstore_2', stacksub=2, maxLocals=4},	-- value → .... store a double into local variable 2
	[0x4a] = {name='dstore_3', stacksub=2, maxLocals=5},	-- value → .... store a double into local variable 3
	[0x4b] = {name='astore_0', stacksub=1, maxLocals=1},	-- objectref → .... store a reference into local variable 0
	[0x4c] = {name='astore_1', stacksub=1, maxLocals=2},	-- objectref → .... store a reference into local variable 1
	[0x4d] = {name='astore_2', stacksub=1, maxLocals=3},	-- objectref → .... store a reference into local variable 2
	[0x4e] = {name='astore_3', stacksub=1, maxLocals=4},	-- objectref → .... store a reference into local variable 3
	[0x4f] = {name='iastore', stacksub=3},	-- arrayref, index, value → .... store an int into an array
	[0x50] = {name='lastore', stacksub=4},	-- arrayref, index, value → .... store a long to an array
	[0x51] = {name='fastore', stacksub=3},	-- arrayref, index, value → .... store a float in an array
	[0x52] = {name='dastore', stacksub=4},	-- arrayref, index, value → .... store a double into an array
	[0x53] = {name='aastore', stacksub=3},	-- arrayref, index, value → .... store a reference in an array
	[0x54] = {name='bastore', stacksub=3},	-- arrayref, index, value → .... store a byte or Boolean value into an array
	[0x55] = {name='castore', stacksub=3},	-- arrayref, index, value → .... store a char into an array
	[0x56] = {name='sastore', stacksub=3},	-- arrayref, index, value → .... store short to array
	[0x57] = {name='pop', stacksub=1},	-- value → .... discard the top value on the stack
	[0x58] = {name='pop2', stacksub=2},	-- {value2, value1} → .... discard the top two values on the stack (or one value, if it is a double or long)
	[0x59] = {name='dup', stackadd=2, stacksub=1},	-- value → value, value .... duplicate the value on top of the stack
	[0x5a] = {name='dup_x1', stackadd=3, stacksub=2},	-- value2, value1 → value1, value2, value1 .... insert a copy of the top value into the stack two values from the top. value1 and value2 must not be of the type double or long.
	[0x5b] = {name='dup_x2', stackadd=4, stacksub=3},	-- value3, value2, value1 → value1, value3, value2, value1 .... insert a copy of the top value into the stack two (if value2 is double or long it takes up the entry of value3, too) or three values (if value2 is neither double nor long) from the top
	[0x5c] = {name='dup2', stackadd=4, stacksub=2},	-- {value2, value1} → {value2, value1}, {value2, value1} .... duplicate top two stack words (two values, if value1 is not double nor long; a single value, if value1 is double or long)
	[0x5d] = {name='dup2_x1', stackadd=5, stacksub=3},	-- value3, {value2, value1} → {value2, value1}, value3, {value2, value1} .... duplicate two words and insert beneath third word (see explanation above)
	[0x5e] = {name='dup2_x2', stackadd=6, stacksub=4},	-- {value4, value3}, {value2, value1} → {value2, value1}, {value4, value3}, {value2, value1} .... duplicate two words and insert beneath fourth word
	[0x5f] = {name='swap', stackadd=2, stacksub=2},	-- value2, value1 → value1, value2 .... swaps two top words on the stack (note that value1 and value2 must not be double or long)
	[0x60] = {name='iadd', stackadd=1, stacksub=2},	-- value1, value2 → result .... add two ints
	[0x61] = {name='ladd', stackadd=2, stacksub=4},	-- value1, value2 → result .... add two longs
	[0x62] = {name='fadd', stackadd=1, stacksub=2},	-- value1, value2 → result .... add two floats
	[0x63] = {name='dadd', stackadd=2, stacksub=4},	-- value1, value2 → result .... add two doubles
	[0x64] = {name='isub', stackadd=1, stacksub=2},	-- value1, value2 → result .... int subtract
	[0x65] = {name='lsub', stackadd=2, stacksub=4},	-- value1, value2 → result .... subtract two longs
	[0x66] = {name='fsub', stackadd=1, stacksub=2},	-- value1, value2 → result .... subtract two floats
	[0x67] = {name='dsub', stackadd=2, stacksub=4},	-- value1, value2 → result .... subtract a double from another
	[0x68] = {name='imul', stackadd=1, stacksub=2},	-- value1, value2 → result .... multiply two integers
	[0x69] = {name='lmul', stackadd=2, stacksub=4},	-- value1, value2 → result .... multiply two longs
	[0x6a] = {name='fmul', stackadd=1, stacksub=2},	-- value1, value2 → result .... multiply two floats
	[0x6b] = {name='dmul', stackadd=2, stacksub=4},	-- value1, value2 → result .... multiply two doubles
	[0x6c] = {name='idiv', stackadd=1, stacksub=2},	-- value1, value2 → result .... divide two integers
	[0x6d] = {name='ldiv', stackadd=2, stacksub=4},	-- value1, value2 → result .... divide two longs
	[0x6e] = {name='fdiv', stackadd=1, stacksub=2},	-- value1, value2 → result .... divide two floats
	[0x6f] = {name='ddiv', stackadd=2, stacksub=4},	-- value1, value2 → result .... divide two doubles
	[0x70] = {name='irem', stackadd=1, stacksub=2},	-- value1, value2 → result .... logical int remainder
	[0x71] = {name='lrem', stackadd=2, stacksub=4},	-- value1, value2 → result .... remainder of division of two longs
	[0x72] = {name='frem', stackadd=1, stacksub=2},	-- value1, value2 → result .... get the remainder from a division between two floats
	[0x73] = {name='drem', stackadd=2, stacksub=4},	-- value1, value2 → result .... get the remainder from a division between two doubles
	[0x74] = {name='ineg', stackadd=1, stacksub=1},	-- value → result .... negate int
	[0x75] = {name='lneg', stackadd=2, stacksub=2},	-- value → result .... negate a long
	[0x76] = {name='fneg', stackadd=1, stacksub=1},	-- value → result .... negate a float
	[0x77] = {name='dneg', stackadd=2, stacksub=2},	-- value → result .... negate a double
	[0x78] = {name='ishl', stackadd=1, stacksub=2},	-- value1, value2 → result .... int shift left
	[0x79] = {name='lshl', stackadd=2, stacksub=3},	-- value1, value2 → result .... bitwise shift left of a long value1 by int value2 positions
	[0x7a] = {name='ishr', stackadd=1, stacksub=2},	-- value1, value2 → result .... int arithmetic shift right
	[0x7b] = {name='lshr', stackadd=2, stacksub=3},	-- value1, value2 → result .... bitwise shift right of a long value1 by int value2 positions
	[0x7c] = {name='iushr', stackadd=1, stacksub=2},	-- value1, value2 → result .... int logical shift right
	[0x7d] = {name='lushr', stackadd=2, stacksub=3},	-- value1, value2 → result .... bitwise shift right of a long value1 by int value2 positions, unsigned
	[0x7e] = {name='iand', stackadd=1, stacksub=2},	-- value1, value2 → result .... perform a bitwise AND on two integers
	[0x7f] = {name='land', stackadd=2, stacksub=4},	-- value1, value2 → result .... bitwise AND of two longs
	[0x80] = {name='ior', stackadd=1, stacksub=2},	-- value1, value2 → result .... bitwise int OR
	[0x81] = {name='lor', stackadd=2, stacksub=4},	-- value1, value2 → result .... bitwise OR of two longs
	[0x82] = {name='ixor', stackadd=1, stacksub=2},	-- value1, value2 → result .... int xor
	[0x83] = {name='lxor', stackadd=2, stacksub=4},	-- value1, value2 → result .... bitwise XOR of two longs

	-- 2: index, const .... [No change] .... increment local variable #index by signed byte const
	[0x84] = {
		name='iinc',
		args={'uint8_t', 'int8_t'},
		maxLocals = function(inst)
			-- iinc $localIndex $amount
			local localIndex = assert(tonumber(inst[2]))
			return localIndex + 1
		end,
	},

	[0x85] = {name='i2l', stackadd=2, stacksub=1},	-- value → result .... convert an int into a long
	[0x86] = {name='i2f', stackadd=1, stacksub=1},	-- value → result .... convert an int into a float
	[0x87] = {name='i2d', stackadd=2, stacksub=1},	-- value → result .... convert an int into a double
	[0x88] = {name='l2i', stackadd=1, stacksub=2},	-- value → result .... convert a long to a int
	[0x89] = {name='l2f', stackadd=1, stacksub=2},	-- value → result .... convert a long to a float
	[0x8a] = {name='l2d', stackadd=2, stacksub=2},	-- value → result .... convert a long to a double
	[0x8b] = {name='f2i', stackadd=1, stacksub=1},	-- value → result .... convert a float to an int
	[0x8c] = {name='f2l', stackadd=2, stacksub=1},	-- value → result .... convert a float to a long
	[0x8d] = {name='f2d', stackadd=2, stacksub=1},	-- value → result .... convert a float to a double
	[0x8e] = {name='d2i', stackadd=1, stacksub=2},	-- value → result .... convert a double to an int
	[0x8f] = {name='d2l', stackadd=2, stacksub=2},	-- value → result .... convert a double to a long
	[0x90] = {name='d2f', stackadd=1, stacksub=2},	-- value → result .... convert a double to a float
	[0x91] = {name='i2b', stackadd=1, stacksub=1},	-- value → result .... convert an int into a byte
	[0x92] = {name='i2c', stackadd=1, stacksub=1},	-- value → result .... convert an int into a character
	[0x93] = {name='i2s', stackadd=1, stacksub=1},	-- value → result .... convert an int into a short
	[0x94] = {name='lcmp', stackadd=1, stacksub=4},	-- value1, value2 → result .... push 0 if the two longs are the same, 1 if value1 is greater than value2, -1 otherwise
	[0x95] = {name='fcmpl', stackadd=1, stacksub=2},	-- value1, value2 → result .... compare two floats, -1 on NaN
	[0x96] = {name='fcmpg', stackadd=1, stacksub=2},	-- value1, value2 → result .... compare two floats, 1 on NaN
	[0x97] = {name='dcmpl', stackadd=1, stacksub=4},	-- value1, value2 → result .... compare two doubles, -1 on NaN
	[0x98] = {name='dcmpg', stackadd=1, stacksub=4},	-- value1, value2 → result .... compare two doubles, 1 on NaN
	[0x99] = {name='ifeq', args={'int16_t'}, stacksub=1},	-- 2: branchbyte1, branchbyte2 .... value → .... if value is 0, branch to instruction at branchoffset (signed short constructed from unsigned bytes branchbyte1 << 8 | branchbyte2)
	[0x9a] = {name='ifne', args={'int16_t'}, stacksub=1},	-- 2: branchbyte1, branchbyte2 .... value → .... if value is not 0, branch to instruction at branchoffset (signed short constructed from unsigned bytes branchbyte1 << 8 | branchbyte2)
	[0x9b] = {name='iflt', args={'int16_t'}, stacksub=1},	-- 2: branchbyte1, branchbyte2 .... value → .... if value is less than 0, branch to instruction at branchoffset (signed short constructed from unsigned bytes branchbyte1 << 8 | branchbyte2)
	[0x9c] = {name='ifge', args={'int16_t'}, stacksub=1},	-- 2: branchbyte1, branchbyte2 .... value → .... if value is greater than or equal to 0, branch to instruction at branchoffset (signed short constructed from unsigned bytes branchbyte1 << 8 | branchbyte2)
	[0x9d] = {name='ifgt', args={'int16_t'}, stacksub=1},	-- 2: branchbyte1, branchbyte2 .... value → .... if value is greater than 0, branch to instruction at branchoffset (signed short constructed from unsigned bytes branchbyte1 << 8 | branchbyte2)
	[0x9e] = {name='ifle', args={'int16_t'}, stacksub=1},	-- 2: branchbyte1, branchbyte2 .... value → .... if value is less than or equal to 0, branch to instruction at branchoffset (signed short constructed from unsigned bytes branchbyte1 << 8 | branchbyte2)
	[0x9f] = {name='if_icmpeq', args={'int16_t'}, stacksub=2},	-- 2: branchbyte1, branchbyte2 .... value1, value2 → .... if ints are equal, branch to instruction at branchoffset (signed short constructed from unsigned bytes branchbyte1 << 8 | branchbyte2)
	[0xa0] = {name='if_icmpne', args={'int16_t'}, stacksub=2},	-- 2: branchbyte1, branchbyte2 .... value1, value2 → .... if ints are not equal, branch to instruction at branchoffset (signed short constructed from unsigned bytes branchbyte1 << 8 | branchbyte2)
	[0xa1] = {name='if_icmplt', args={'int16_t'}, stacksub=2},	-- 2: branchbyte1, branchbyte2 .... value1, value2 → .... if value1 is less than value2, branch to instruction at branchoffset (signed short constructed from unsigned bytes branchbyte1 << 8 | branchbyte2)
	[0xa2] = {name='if_icmpge', args={'int16_t'}, stacksub=2},	-- 2: branchbyte1, branchbyte2 .... value1, value2 → .... if value1 is greater than or equal to value2, branch to instruction at branchoffset (signed short constructed from unsigned bytes branchbyte1 << 8 | branchbyte2)
	[0xa3] = {name='if_icmpgt', args={'int16_t'}, stacksub=2},	-- 2: branchbyte1, branchbyte2 .... value1, value2 → .... if value1 is greater than value2, branch to instruction at branchoffset (signed short constructed from unsigned bytes branchbyte1 << 8 | branchbyte2)
	[0xa4] = {name='if_icmple', args={'int16_t'}, stacksub=2},	-- 2: branchbyte1, branchbyte2 .... value1, value2 → .... if value1 is less than or equal to value2, branch to instruction at branchoffset (signed short constructed from unsigned bytes branchbyte1 << 8 | branchbyte2)
	[0xa5] = {name='if_acmpeq', args={'int16_t'}, stacksub=2},	-- 2: branchbyte1, branchbyte2 .... value1, value2 → .... if references are equal, branch to instruction at branchoffset (signed short constructed from unsigned bytes branchbyte1 << 8 | branchbyte2)
	[0xa6] = {name='if_acmpne', args={'int16_t'}, stacksub=2},	-- 2: branchbyte1, branchbyte2 .... value1, value2 → .... if references are not equal, branch to instruction at branchoffset (signed short constructed from unsigned bytes branchbyte1 << 8 | branchbyte2)
	[0xa7] = {name='goto', args={'int16_t'}},	-- 2: branchbyte1, branchbyte2 .... [no change] .... goes to another instruction at branchoffset (signed short constructed from unsigned bytes branchbyte1 << 8 | branchbyte2)
	[0xa8] = {name='jsr', args={'int16_t'}, stackadd=1},	-- 2: branchbyte1, branchbyte2 .... → address .... jump to subroutine at branchoffset (signed short constructed from unsigned bytes branchbyte1 << 8 | branchbyte2) and place the return address on the stack

	-- 1: index .... [No change] .... continue execution from address taken from a local variable #index (the asymmetry with jsr is intentional)
	[0xa9] = {
		name='ret',
		args={'int8_t'},
		maxLocals = function(inst)
			local localIndex = assert(tonumber(inst[2]))
			return localIndex + 1
		end,
	},

	-- 16+: [0–3 bytes padding], defaultbyte1, defaultbyte2, defaultbyte3, defaultbyte4, lowbyte1, lowbyte2, lowbyte3, lowbyte4, highbyte1, highbyte2, highbyte3, highbyte4, jump offsets... .... index → .... continue execution from an address in the table at offset index
	[0xaa] = {name='tableswitch',
		args = function() error'TODO' end,	--...
		stacksub = 1,
	},

	-- 8+: <0–3 bytes padding>, defaultbyte1, defaultbyte2, defaultbyte3, defaultbyte4, npairs1, npairs2, npairs3, npairs4, match-offset pairs... .... key → .... a target address is looked up from a table using a key and execution continues from the instruction at that address
	[0xab] = {name='lookupswitch',
		args = function() error'TODO' end,
		stacksub = 1,
	},

	[0xac] = {name='ireturn', stacksub=1},	-- value → [empty] .... return an integer from a method
	[0xad] = {name='lreturn', stacksub=2},	-- value → [empty] .... return a long value
	[0xae] = {name='freturn', stacksub=1},	-- value → [empty] .... return a float
	[0xaf] = {name='dreturn', stacksub=2},	-- value → [empty] .... return a double from a method
	[0xb0] = {name='areturn', stacksub=1},	-- objectref → [empty] .... return a reference from a method
	[0xb1] = {name='return'},	-- → [empty] .... return from a void method

	-- 2: indexbyte1, indexbyte2 .... → value .... get a static field value of a class, where the field is identified by field reference in the constant pool index (indexbyte1 << 8 | indexbyte2)
	[0xb2] = {
		name='getstatic',
		--args={'uint16_t'},
		stackadd = function(inst, curStack)	-- NOTICE this will depend on the field type
			-- getstatic $class $fieldName $fieldSig
			local fieldSig = assert.index(inst, 4)
			if fieldSig == 'J' or fieldsig == 'D' then
				return curStack + 2
			end
			return curStack + 1
		end,
		args = function(inst, insBlob, asmClass)
			instPushField(inst, insBlob, asmClass)
		end,
		write = function(inst, insBlob, asmClass)
			insBlob:writeu2(instPopField(inst, 2, asmClass))
		end,
	},

	-- 2: indexbyte1, indexbyte2 .... value → .... set static field to value in a class, where the field is identified by a field reference index in constant pool (indexbyte1 << 8 | indexbyte2)
	[0xb3] = {
		name='putstatic',
		--args={'uint16_t'},
		stacksub = function(inst, curStack)	-- NOTICE this will depend on the field type
			-- putstatic $class $fieldName $fieldSig
			local fieldSig = assert.index(inst, 4)
			if fieldSig == 'J' or fieldSig == 'D' then
				return curStack - 2
			end
			return curStack - 1
		end,
		args = function(inst, insBlob, asmClass)
			instPushField(inst, insBlob, asmClass)
		end,
		write = function(inst, insBlob, asmClass)
			insBlob:writeu2(instPopField(inst, 2, asmClass))
		end,
	},

	-- 2: indexbyte1, indexbyte2 .... objectref → value .... get a field value of an object objectref, where the field is identified by field reference in the constant pool index (indexbyte1 << 8 | indexbyte2)
	[0xb4] = {
		name='getfield',
		--args={'uint16_t'},
		stacksub = 1,
		stackadd = function(inst, curStack)	-- NOTICE this will depend on the field type
			-- getfield $class $fieldName $fieldSig
			local fieldSig = assert.index(inst, 4)
			if fieldSig == 'J' or fieldsig == 'D' then
				return curStack + 2
			end
			return curStack + 1
		end,
		args = function(inst, insBlob, asmClass)
			instPushField(inst, insBlob, asmClass)
		end,
		write = function(inst, insBlob, asmClass)
			insBlob:writeu2(instPopField(inst, 2, asmClass))
		end,
	},

	-- 2: indexbyte1, indexbyte2 .... objectref, value → .... set field to value in an object objectref, where the field is identified by a field reference index in constant pool (indexbyte1 << 8 | indexbyte2)
	[0xb5] = {
		name='putfield',
		--args={'uint16_t'},
		stacksub = function(inst, curStack)	-- NOTICE this will depend on the field type ... -1 for removing the object ref
			curStack  = curStack - 1	-- object ref
			-- getfield $class $fieldName $fieldSig
			local fieldSig = assert.index(inst, 4)
			if fieldSig == 'J' or fieldsig == 'D' then
				return curStack - 2
			end
			return curStack - 1
		end,
		args = function(inst, insBlob, asmClass)
			assert(xpcall(function()
				instPushField(inst, insBlob, asmClass)
			end, function(err)
				return 'at putfield at ofs='..insBlob.ofs..'\n'..err
			end))
		end,
		write = function(inst, insBlob, asmClass)
			local fieldIndex = instPopField(inst, 2, asmClass)
--DEBUG:print('write putfield '..fieldIndex)
			insBlob:writeu2(fieldIndex)
		end,
	},

	-- 2: indexbyte1, indexbyte2 .... objectref, [arg1, arg2, ...] → result .... invoke virtual method on object objectref and puts the result on the stack (might be void); the method is identified by method reference index in constant pool (indexbyte1 << 8 | indexbyte2)
	[0xb6] = {
		name='invokevirtual',
		stackadd = function(inst, curStack)	-- NOTICE this depends on return type
			-- invokevirtual $class $methodName $sig
			local sig = assert.index(inst,4)
			if sig:match'J$' or sig:match'D$' then
				return curStack + 2
			elseif sig:match'V$' then
				return curStack
			end
			return curStack + 1
		end,
		stacksub = function(inst, curStack)	-- NOTICE this depends on args
			curStack  = curStack - 1
			local sig = sigStrToObj(assert.index(inst,4))
			for i=2,#sig do
				local sigi = sig[i]
				if sigi == 'long' or sigi == 'double' then
					curStack = curStack - 2
				else
					curStack = curStack - 1
				end
			end
			return curStack
		end,
		args = function(inst, insBlob, asmClass)
			instPushMethod(inst, insBlob, asmClass)
		end,
		write = function(inst, insBlob, asmClass)
			insBlob:writeu2(instPopMethod(inst, 2, asmClass))
		end,
	},

	-- 2: indexbyte1, indexbyte2 .... objectref, [arg1, arg2, ...] → result .... invoke instance method on object objectref and puts the result on the stack (might be void); the method is identified by method reference index in constant pool (indexbyte1 << 8 | indexbyte2)
	[0xb7] = {
		name='invokespecial',
		stackadd = function(inst, curStack)	-- NOTICE this depends on return type
			-- invokespecial $class $methodName $sig
			local sig = assert.index(inst,4)
			if sig:match'J$' or sig:match'D$' then
				return curStack + 2
			elseif sig:match'V$' then
				return curStack
			end
			return curStack + 1
		end,
		stacksub = function(inst, curStack)	-- NOTICE this depends on args
			curStack  = curStack - 1
			local sig = sigStrToObj(assert.index(inst,4))
			for i=2,#sig do
				local sigi = sig[i]
				if sigi == 'long' or sigi == 'double' then
					curStack = curStack - 2
				else
					curStack = curStack - 1
				end
			end
			return curStack
		end,
		args = function(inst, insBlob, asmClass)
			instPushMethod(inst, insBlob, asmClass)
		end,
		write = function(inst, insBlob, asmClass)
			insBlob:writeu2(instPopMethod(inst, 2, asmClass))
		end,
	},

	-- 2: indexbyte1, indexbyte2 .... [arg1, arg2, ...] → result .... invoke a static method and puts the result on the stack (might be void); the method is identified by method reference index in constant pool (indexbyte1 << 8 | indexbyte2)
	[0xb8] = {
		name='invokestatic',
		stackadd = function(inst, curStack)	-- NOTICE this depends on return type
			-- invokestatic $class $methodName $sig
			local sig = assert.index(inst,4)
			if sig:match'J$' or sig:match'D$' then
				return curStack + 2
			elseif sig:match'V$' then
				return curStack
			end
			return curStack + 1
		end,
		stacksub = function(inst, curStack)	-- NOTICE this depends on args
			-- no -1 since no object
			local sig = sigStrToObj(assert.index(inst,4))
			for i=2,#sig do
				local sigi = sig[i]
				if sigi == 'long' or sigi == 'double' then
					curStack = curStack - 2
				else
					curStack = curStack - 1
				end
			end
			return curStack
		end,
		args = function(inst, insBlob, asmClass)
			instPushMethod(inst, insBlob, asmClass)
		end,
		write = function(inst, insBlob, asmClass)
			insBlob:writeu2(instPopMethod(inst, 2, asmClass))
		end,
	},

	-- 4: indexbyte1, indexbyte2, count, 0 .... objectref, [arg1, arg2, ...] → result .... invokes an interface method on object objectref and puts the result on the stack (might be void); the interface method is identified by method reference index in constant pool (indexbyte1 << 8 | indexbyte2)
	[0xb9] = {
		name='invokeinterface',
		stackadd = function(inst, curStack)	-- NOTICE this depends on return type
			-- invokeinterface $class $methodName $sig
			local sig = assert.index(inst,4)
			if sig:match'J$' or sig:match'D$' then
				return curStack + 2
			elseif sig:match'V$' then
				return curStack
			end
			return curStack + 1
		end,
		stacksub = function(inst, curStack)	-- NOTICE this depends on args
			curStack  = curStack - 1
			local sig = sigStrToObj(assert.index(inst,4))
			for i=2,#sig do
				local sigi = sig[i]
				if sigi == 'long' or sigi == 'double' then
					curStack = curStack - 2
				else
					curStack = curStack - 1
				end
			end
			return curStack
		end,
		args = function(inst, insBlob, asmClass)
			instPushMethod(inst, insBlob, asmClass)
			inst:insert(insBlob:readu1())	-- count ... what's count for?
			assert.eq(insBlob:readu1(), 0)	-- 0
		end,
		write = function(inst, insBlob, asmClass)
			local methodIndex, index = instPopMethod(inst, 2, asmClass)
			insBlob:writeu2(methodIndex)
			insBlob:writeu1(inst[index])
			insBlob:writeu1(0)
		end,
	},

	-- 4: indexbyte1, indexbyte2, 0, 0 .... [arg1, arg2, ...] → result .... invokes a dynamic method and puts the result on the stack (might be void); the method is identified by method reference index in constant pool (indexbyte1 << 8 | indexbyte2)
	[0xba] = {
		name='invokedynamic',
		stackadd = function(inst, curStack)	-- NOTICE this depends on return type
			-- invokedynamic $class $methodName $sig
			local sig = assert.index(inst,4)
			if sig:match'J$' or sig:match'D$' then
				return curStack + 2
			elseif sig:match'V$' then
				return curStack
			end
			return curStack + 1
		end,
		stacksub = function(inst, curStack)	-- NOTICE this depends on args
			-- TODO what is a dynamic method, and how come there's no object ref?
			local sig = sigStrToObj(assert.index(inst,4))
			for i=2,#sig do
				local sigi = sig[i]
				if sigi == 'long' or sigi == 'double' then
					curStack = curStack - 2
				else
					curStack = curStack - 1
				end
			end
			return curStack
		end,
		--args={'uint16_t', 'uint8_t', 'uint8_t'},
		args = function(inst, insBlob, asmClass)
			instPushMethod(inst, insBlob, asmClass)
			assert.eq(insBlob:readu2(), 0)	-- why are there uint16 of 0 when this is a uint32 method?
		end,
		write = function(inst, insBlob, asmClass)
			insBlob:writeu2(instPopMethod(inst, 2, asmClass))
			insBlob:writeu2(0)
		end,
	},

	-- 2: indexbyte1, indexbyte2 .... → objectref .... create new object of type identified by class reference in constant pool index (indexbyte1 << 8 | indexbyte2)
	[0xbb] = {
		name='new',
		stackadd = 1,
		--args={'uint16_t'},
		args = function(inst, insBlob, asmClass)
			instPushClass(inst, insBlob, asmClass)
		end,
		write = function(inst, insBlob, asmClass)
			insBlob:writeu2(insPopClass(inst, 2, asmClass))
		end,
	},

	-- 1: atype .... count → arrayref .... create new array with count elements of primitive type identified by atype
	[0xbc] = {
		name='newarray',
		stacksub = 1,
		stackadd = 1,
		args={'uint8_t'},
		-- TODO args is atype is a primitive type
	},

	-- 2: indexbyte1, indexbyte2 .... count → arrayref .... create a new array of references of length count and component type identified by the class reference index (indexbyte1 << 8 | indexbyte2) in the constant pool
	[0xbd] = {
		name='anewarray',
		--args={'uint16_t'},
		stacksub = 1,
		stackadd = 1,
		args = function(inst, insBlob, asmClass)
			instPushClass(inst, insBlob, asmClass)
		end,
		write = function(inst, insBlob, asmClass)
			insBlob:writeu2(insPopClass(inst, 2, asmClass))
		end,
	},

	[0xbe] = {name='arraylength', stacksub=1, stackadd=1},	-- arrayref → length .... get the length of an array
	[0xbf] = {name='athrow', stackadd=function() return 1 end},	-- objectref → [empty], objectref .... throws an error or exception (notice that the rest of the stack is cleared, leaving only a reference to the Throwable)

	-- 2: indexbyte1, indexbyte2 .... objectref → objectref .... checks whether an objectref is of a certain type, the class reference of which is in the constant pool at index (indexbyte1 << 8 | indexbyte2)
	[0xc0] = {
		name='checkcast',
		stacksub = 1,
		stackadd = 1,
		--args={'uint16_t'},
		args = function(inst, insBlob, asmClass)
			instPushClass(inst, insBlob, asmClass)
		end,
		write = function(inst, insBlob, asmClass)
			insBlob:writeu2(insPopClass(inst, 2, asmClass))
		end,
	},

	-- 2: indexbyte1, indexbyte2 .... objectref → result .... determines if an object objectref is of a given type, identified by class reference index in constant pool (indexbyte1 << 8 | indexbyte2)
	[0xc1] = {
		name='instanceof',
		stacksub = 1,
		stackadd = 1,
		--args={'uint16_t'},
		args = function(inst, insBlob, asmClass)
			instPushClass(inst, insBlob, asmClass)
		end,
		write = function(inst, insBlob, asmClass)
			insBlob:writeu2(insPopClass(inst, 2, asmClass))
		end,
	},

	[0xc2] = {name='monitorenter', stacksub=1},	-- objectref → .... enter monitor for object ("grab the lock" – start of synchronized() section)
	[0xc3] = {name='monitorexit', stacksub=1},	-- objectref → .... exit monitor for object ("release the lock" – end of synchronized() section)
	[0xc4] = {name='wide', args=function() error'TODO' end, stackadd = function() error'TODO' end},	-- 3/5: opcode, indexbyte1, indexbyte2 or iinc, indexbyte1, indexbyte2, countbyte1, countbyte2 .... [same as for corresponding instructions] .... execute opcode, where opcode is either iload, fload, aload, lload, dload, istore, fstore, astore, lstore, dstore, or ret, but assume the index is 16 bit; or execute iinc, where the index is 16 bits and the constant to increment by is a signed 16 bit short

	-- 3: indexbyte1, indexbyte2, dimensions .... count1, [count2,...] → arrayref .... create a new array of dimensions dimensions of type identified by class reference in constant pool index (indexbyte1 << 8 | indexbyte2); the sizes of each dimension is identified by count1, [count2, etc.]
	[0xc5] = {
		name='multianewarray',
		stacksub = function(inst, curStack)
			-- inst = {'multianewarray' indexhi, indexlo, dimension}
			local dim = assert(tonumber(inst[4]))
			curStack = curStack - dim
		end,
		stackadd = 1,	-- new ref
		--args={'uint16_t', 'uint8_t'}
		args = function(inst, insBlob, asmClass)
			instPushClass(inst, insBlob, asmClass)
			inst:insert(insBlob:readu1())
		end,
		write = function(inst, insBlob, asmClass)
			local classIndex, index = insPopClass(inst, 2, asmClass)
			insBlob:writeu2(classIndex)
			insBlob:writeu1(inst[index])
		end,
	},

	[0xc6] = {name='ifnull', args={'int16_t'}, stacksub=1},	-- 2: branchbyte1, branchbyte2 .... value → .... if value is null, branch to instruction at branchoffset (signed short constructed from unsigned bytes branchbyte1 << 8 | branchbyte2)
	[0xc7] = {name='ifnonnull', args={'int16_t'}, stacksub=1},	-- 2: branchbyte1, branchbyte2 .... value → .... if value is not null, branch to instruction at branchoffset (signed short constructed from unsigned bytes branchbyte1 << 8 | branchbyte2)
	[0xc8] = {name='goto_w', args={'int32_t'}},	-- 4: branchbyte1, branchbyte2, branchbyte3, branchbyte4 .... [no change] .... goes to another instruction at branchoffset (signed int constructed from unsigned bytes branchbyte1 << 24 | branchbyte2 << 16 | branchbyte3 << 8 | branchbyte4)
	[0xc9] = {name='jsr_w', args={'int32_t'}, stackadd=1},	-- 4: branchbyte1, branchbyte2, branchbyte3, branchbyte4 .... → address .... jump to subroutine at branchoffset (signed int constructed from unsigned bytes branchbyte1 << 24 | branchbyte2 << 16 | branchbyte3 << 8 | branchbyte4) and place the return address on the stack
	[0xca] = {name='breakpoint'},	-- reserved for breakpoints in Java debuggers; should not appear in any class file
	[0xfe] = {name='impdep1'},	-- reserved for implementation-dependent operations within debuggers; should not appear in any class file
	[0xff] = {name='impdep2'},	-- reserved for implementation-dependent operations within debuggers; should not appear in any class file
	--(no name) .... cb-fd ....  ....  ....  .... these values are currently unassigned for opcodes and are reserved for future use
}

local opForInstName = table.map(instDescForOp, function(inst,op)
	return op, inst.name
end)


local JavaASMClass = class()
JavaASMClass.__name = 'JavaASMClass'

-- ; is a popular asm comment syntax, right?
JavaASMClass.lineComment = ';'

function JavaASMClass:init(args)
	if type(args) == 'string' then
		self:readData(args)	-- assume its raw data
	elseif type(args) == 'nil' then
	elseif type(args) == 'table' then
		for k,v in pairs(args) do
			self[k] = v
		end

		-- while we're here, prepare / validate args:
		for _,method in ipairs(self.methods) do
			-- parse method.code if it is instructions
			if type(method.code) == 'string' then

				-- argument validation:
				-- do this here or upon ctor?
				method.code = string.split(string.trim(method.code), '\n')
					:mapi(function(line)
						return string.trim(line)
					end)
					:filteri(function(line)
						return line:sub(1, #self.lineComment) ~= self.lineComment
					end)
					:mapi(function(line)
						return string.split(line, '%s+')
					end)

			end
		end
	else
		error("idk how to init this")
	end
end


-------------------------------- READING --------------------------------


-- static ctor
function JavaASMClass:fromFile(filename)
	local o = JavaASMClass()
	o:readData((assert(path(filename):read())))
	return o
end

function JavaASMClass:readData(data)
	local function deepCopyIndex(index)
		return deepCopy(assert.index(self.constants, index))
	end

	--[[
	this uses deepCopyIndex on name
	but does so only after self.constants is deep-copied
	also assets the name is a string.
	this reads the length but then leaves it up to the callback to read the proper data
	--]]
	local function readAttrs(b, callback)
		local attrCount = b:readu2()
		if attrCount == 0 then return end
		for i=0,attrCount-1 do
			local name = deepCopyIndex(b:readu2())	-- index into constants[]
			assert.type(name, 'string')
			local length = b:readu4()
			local startOfs = b.ofs
			callback(name, length, i)
			assert.eq(startOfs + length, b.ofs, "readAttrs callback read wrong")
		end
	end

	local blob = ReadBlob(data)
	local magic = blob:readu4()
	assert.eq(magic, 0xcafebabe)
	local version = blob:readu4()
--DEBUG:print(('version 0x%x'):format(version))
	-- store version info or nah?
	local constantCount = blob:readu2()
	self.constants = table()
	do
		local skipnext
		for i=1,constantCount-1 do
			if not skipnext then
				local tag = blob:readu1()
				local const = {index=i, tag=tag}
				if tag == 7 then		-- class
					const.tag = 'class'
					const.nameIndex = blob:readu2()
				elseif tag == 9 then		-- fieldref
					const.tag = 'fieldRef'
					const.classIndex = blob:readu2()
					const.nameAndTypeIndex = blob:readu2()
				elseif tag == 10 then			-- methodref
					const.tag = 'methodRef'
					const.classIndex = blob:readu2()
					const.nameAndTypeIndex = blob:readu2()
				elseif tag == 11 then 			-- interfaceMethodRef
					const.tag = 'interfaceMethodRef'
					const.classIndex = blob:readu2()
					const.nameAndTypeIndex = blob:readu2()

				elseif tag == 8 then	-- string ... string literal
					const.tag = 'string'
					const.valueIndex = blob:readu2()
				elseif tag == 3 then	-- integer
					const.tag = 'int'
					const.value = blob:read'jint'
				elseif tag == 4 then	-- float
					const.tag = 'float'
					const.value = blob:read'jfloat'
				elseif tag == 5 then	-- long
					const.tag = 'long'
					const.value = blob:read'jlong'
					-- "all 8-byte constants take up 2 entries in the const pool ..." wrt their data only, right? no extra tag in there right?
					skipnext = true
				elseif tag == 6 then	-- double
					const.tag = 'double'
					const.value = blob:read'jdouble'
					skipnext = true

				elseif tag == 12 then	-- nameAndType
					const.tag = 'nameAndType'
					const.nameIndex = blob:readu2()
					const.sigIndex = blob:readu2()
				elseif tag == 1 then 	-- utf8string ... the string data
					local length = blob:readu2()
					--[[ keep a table?
					const.tag = 'utf8string'
					const.value = blob:readString(length)
					--]]
					-- [[ or nah?
					const = blob:readString(length)
					--]]
				elseif tag == 15 then	-- methodHandle
					const.tag = 'methodHandle'
					local refKind = blob:readu2()
					const.refKind = assert.index({
						'getField',
						'getStatic',
						'putField',
						'putStatic',
						'invokeVirtual',
						'invokeStatic',
						'invokeSpecial',
						'newInvokeSpecial',
						'invokeInterface',
					}, refKind)
					const.referenceIndex = blob:readu2()
				elseif tag == 16 then	-- methodType
					const.tag = 'methodType'
					const.sigIndex = blob:readu2()
				elseif tag == 18 then	-- invokeDynamic
					const.tag = 'invokeDynamic'
					const.bootstrapMethodAttrIndex = blob:readu2()
					const.nameAndTypeIndex = blob:readu2()
				elseif tag == 19 then	-- module
					const.tag = 'module'
					const.nameIndex = blob:readu2()
				elseif tag == 20 then	-- package
					const.tag = 'package'
					const.nameIndex = blob:readu2()
				else
					error('unknown tag '..tostring(tag)..' / 0x'..bit.tohex(tag, 2)
						..' at offset 0x'..bit.tohex(ofs)
					)
				end
--DEBUG:print('reading const', i, require 'ext.tolua'(const))
				self.constants:insert(const)
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
	for constIndex,const in ipairs(self.constants) do
		if type(const) == 'table' then 	-- skip fillers for double and long
			const.index = nil
			-- TODO TODO also assert matching type?
			if const.nameIndex then
				const.name = assert.type(assert.index(self.constants, const.nameIndex), 'string')
				const.nameIndex = nil
			end
			if const.classIndex then
				const.class = assert.index(self.constants, const.classIndex)
				const.classIndex = nil
			end
			if const.nameAndTypeIndex then
				const.nameAndType = self.constants[const.nameAndTypeIndex]
if not const.nameAndType then
	error('const '..constIndex..' tag '..const.tag..' has nameAndType oob '..const.nameAndTypeIndex)
end
				const.nameAndTypeIndex = nil
			end
			if const.valueIndex then
				const.value = assert.index(self.constants, const.valueIndex)
				const.valueIndex = nil
			end
			if const.sigIndex then
				const.sig = assert.index(self.constants, const.sigIndex)
				const.sigIndex = nil
			end
			if const.referenceIndex then
				const.reference = assert.index(self.constants, const.referenceIndex)
				const.referenceIndex = nil
			-- maybe this is to the attrs[] list?
			end
			if const.bootstrapMethodAttrIndex then
				const.bootstrapMethodAttr = assert.index(self.constants, const.bootstrapMethodAttrIndex)
				const.bootstrapMethodAttrIndex = nil
			end
		end
	end

	-- only after constants refs are set, now deep copy
	-- (since constants has out-of-order refs)
	self.constants = deepCopy(self.constants)


	--self.accessFlags = blob:readu2()
	setFlagsToObj(self, blob:readu2(), classAccessFlags)

	self.thisClass = readClassName(self, blob:readu2())
	self.superClass = readClassName(self, blob:readu2())

	local interfaceCount = blob:readu2()
	if interfaceCount > 0 then
		self.interfaces = table()
		for i=1,interfaceCount do
			local interface = assert.index(self.constants, blob:readu2())
			assert.eq(interface.tag, 'class')
			self.interfaces:insert((assert(interface.name)))
		end
	end

	local fieldCount = blob:readu2()
	self.fields = table()
	for fieldIndex=1,fieldCount do
		local field = {}

		--field.accessFlags = blob:readu2()
		setFlagsToObj(field, blob:readu2(), fieldAccessFlags)

		field.name = deepCopyIndex(blob:readu2())
		field.sig = deepCopyIndex(blob:readu2())

		field.attrs = table()
		readAttrs(blob, function(fieldAttrName, fieldAttrLen)
			if fieldAttrName == 'ConstantValue' then
				assert(not field.value, 'field cannot have two "ConstantValue" attributes')
				assert.eq(fieldAttrLen, 2, 'field attr "ConstantValue" must be 2 bytes')
				field.value = deepCopyIndex(blob:readu2())
			else
io.stderr:write('TODO not yet supported field attr: '..fieldAttrName)
				field.attrs:insert{
					name = fieldAttrName,
					data = blob:readString(fieldAttrLen),
				}
			end
		end)
		if #field.attrs == 0 then field.attrs = nil end

		self.fields:insert(field)
--DEBUG:print('reading field', fieldIndex, require 'ext.tolua'(field))
	end

	local methodCount = blob:readu2()
	self.methods = table()
	for methodIndex=1,methodCount do
		local method = {}

		--method.accessFlags = blob:readu2()
		setFlagsToObj(method, blob:readu2(), methodAccessFlags)

		method.name = deepCopyIndex(blob:readu2())
		method.sig = deepCopyIndex(blob:readu2())

		-- method attribute #1 = code attribute
		method.attrs = table()
		readAttrs(blob, function(methodAttrName, methodAttrLen)
--DEBUG:local methodAttrData = blob.data:sub(blob.ofs+1, blob.ofs+methodAttrLen)
--DEBUG:print('reading method '..methodIndex..' methodAttrData '..#methodAttrData)
--DEBUG:print(require 'ext.string'.hexdump(methodAttrData))

			-- I could have method.attrs = {{name='Code, etc}, ...}
			-- but because these attributes are 1) unique and 2) required (method's "Code" and field's "ConstantValue"),
			--  instead I'll just write them as extra arguments to the method.
			if methodAttrName == 'Code' then
				assert(not method.code, 'method cannot have two "Code" attributes')

				local code = table()
				method.code = code

				method.maxStack = blob:readu2()
				method.maxLocals = blob:readu2()
--DEBUG:print('reading method stack locals', method.maxStack, method.maxLocals)

				local insnDataLength = blob:readu4()
				local insnStartOfs = blob.ofs
				local insnEndOfs = insnStartOfs + insnDataLength
				local insBlobData = blob.data:sub(blob.ofs+1, insnDataLength)
--DEBUG:print('reading method '..methodIndex..' insn blob '..#insBlobData)
--DEBUG:print(require 'ext.string'.hexdump(insBlobData))
				-- [[
				while blob.ofs < insnEndOfs do
					local op = blob:readu1()
					local instDesc = assert.index(instDescForOp, op)
					local inst = table()
					inst:insert((assert.index(instDesc, 'name')))
					local argDesc = instDesc.args
					if argDesc then
						if type(argDesc) == 'table' then
							for _,ctype in ipairs(argDesc) do
								inst:insert((blob:read(ctype)))
							end
						elseif type(argDesc) == 'function' then
							argDesc(inst, blob, self)
						else
							error('got unknown inst.args '..type(argDesc))
						end
					end
					code:insert(inst)
				end
				assert.eq(blob.ofs, insnEndOfs)
				--]]

				local exceptionCount = blob:readu2()
				if exceptionCount > 0 then
					method.exceptions = table()
					for exceptionIndex=1,exceptionCount do
						local ex = {}
						ex.startPC = blob:readu2()
						ex.endPC = blob:readu2()
						ex.handlerPC = blob:readu2()
						ex.catchType = deepCopyIndex(blob:readu2())
						method.exceptions:insert(ex)
					end
				end

				-- Because Code is a unique attribute of method,
				-- and since Code's attr "StackMapTable" is also unique,
				-- I'll put method' attr "Code"s attr "StackMapTable" as properties of method as well.
				-- But I can't have method.code.attrs since code is a list of instructions.
				-- so I'll put method's attr Code's attrs into a method.codeAttr table.
				method.codeAttrs = table()

				-- code attribute #1 = stack map attribute
				readAttrs(blob, function(codeAttrName, codeAttrLen)
					if codeAttrName == 'StackMapTable' then
						assert(not method.stackmap, 'method "Code" attribute cannot have two "StackMapTable" attributes')

						local stackmap = {}
						method.stackmap = stackmap

						local smAttrData = blob:readString(codeAttrLen)

io.stderr:write'TODO handle StackMapTable\n'
--[===[ TODO
						local smAttrBlob = ReadBlob(smAttrData)
--DEBUG:print('smAttrData')
--DEBUG:print(require'ext.string'.hexdump(smAttrData))

						local numEntries = smAttrBlob:readu2()
--DEBUG:method.stackMapTableNumEntries = numEntries
						stackmap.frames = table()

						-- next comes an implicit frame ...
						local frame = {}
						-- it has # locals 'maxLocals' and # stacks 'maxStacks' previously read ...
						frame.locals = {}
						stackmap.frames:insert(frame)
						-- do we init the locals to the args?  including 'this' if its not a static method?


						for entryIndex=1,numEntries do
							local smFrame = {}

							local function readVerificationTypeInfo()
								local typeinfo = {}
								typeinfo.tag = smAttrBlob:readu1()
--DEBUG:print('reading verification tag type', typeinfo.tag)
								if tag == 0 then -- top
								elseif tag == 1 then -- integer
								elseif tag == 2 then -- float
								elseif tag == 5 then -- null
								elseif tag == 6 then -- uninitialized 'this'
								elseif tag == 7 then	-- object
									typeinfo.value = deepCopyIndex(smAttrBlob:readu2())
--DEBUG:print('reading verification tag value', typeinfo.value)
								elseif tag == 8 then	-- uninitialized
									typeinfo.offset = smAttrBlob:readu2()
--DEBUG:print('reading verification tag offset', typeinfo.offset)

								elseif tag == 4	-- long
								or tag == 5		-- double
								then
									-- for double and long:
									-- "requires two locations in the local varaibles array"
									-- ... does that mean we skip 2 here as well?
									-- wait am I supposed to be reading the u2 that the others use as well?
									-- but it's long and double ... do I read u4? that's not in specs.
									-- do I just skip the next u1 tag? weird.
									--smAttrBlob:readu1()
									--smAttrBlob:readu2()
									--smAttrBlob:readu4()
								else
									error("unknown verification type tag "..tostring(tag))
								end
								return typeinfo
							end

							local frameType = smAttrBlob:readu1()
--DEBUG:print('reading frameType', frameType)
							smFrame.type = frameType
							if frameType < 64 then
								-- "same"
							elseif frameType < 128 then
								-- "locals 1 stack item"
								smFrame.stack = readVerificationTypeInfo()
							elseif frameType < 247 then
								-- 128-247 = reserved
--DEBUG:print('found reseved stack map frame type', frameType)
							elseif frameType == 247 then
								-- "locals 1 stack item extended"
								smFrame.stack = readVerificationTypeInfo()
							elseif frameType < 251 then
								-- "chop frame"
								smFrame.offsetDelta = smAttrBlob:readu2()
--DEBUG:print('reading smFrame offsetDelta', smFrame.offsetDelta)
							elseif frameType == 251 then
								-- "same frame extended"
								smFrame.offsetDelta = smAttrBlob:readu2()
--DEBUG:print('reading smFrame offsetDelta', smFrame.offsetDelta)
							elseif frameType < 255 then
								-- "append"
								smFrame.offsetDelta = smAttrBlob:readu2()
--DEBUG:print('reading smFrame offsetDelta', smFrame.offsetDelta)
								local numLocals = frameType - 251
								if numLocals > 0 then
									smFrame.locals = {}
									for localIndex=1,numLocals do
										smFrame.locals[localIndex] = readVerificationTypeInfo()
									end
								end
							else
								assert.eq(frameType, 255)
								-- "full frame"
								smFrame.offsetDelta = smAttrBlob:readu2()
--DEBUG:print('reading smFrame offsetDelta', smFrame.offsetDelta)
								local numLocals = smAttrBlob:readu2()
--DEBUG:print('reading smFrame numLocals', numLocals)
								if numLocals > 0 then
									smFrame.locals = {}
									for localIndex=1,numLocals do
										smFrame.locals[localIndex] = readVerificationTypeInfo()
									end
								end
								local numStackItems = smAttrBlob:readu2()
--DEBUG:print('reading smFrame numStackItems', numStackItems)
								if numStackItems > 0 then
									smFrame.stackItems = {}
									for stackItemIndex=1,numStackItems do
										smFrame.stackItems[stackItemIndex] = readVerificationTypeInfo()
									end
								end
							end

							stackmap.frames[entryIndex] = smFrame
						end
						smAttrBlob:assertDone()
--]===]
					elseif codeAttrName == 'LineNumberTable' then
						-- is LineNumberTable unique?
						--  if yes then error upon method.lineNos here
						--  if no then we will append to lineNos as we go
						--  (and that means we will spit out just one attribute even if we read in multiple)
						method.lineNos = method.lineNos or table()

						local numLineNos = blob:readu2()
						for i=1,numLineNos do
							local lineNo = {}
							lineNo.startPC = blob:readu2()
							lineNo.lineNo = blob:readu2()
							method.lineNos:insert(lineNo)
						end
					else
io.stderr:write('TODO not yet supported method "Code" attr: '..codeAttrName)
						method.codeAttrs:insert{
							name = codeAttrName,
							data = blob:readString(codeAttrLen),
						}
					end
				end)
				if #method.codeAttrs == 0 then method.codeAttrs = nil end

			else	-- methodAttr other than Code...
io.stderr:write('TODO not yet supported method attr: '..methodAttrName)
				method.attrs:insert{
					name = methodAttrName,
					data = blob:readString(methodAttrLen),
				}
			end
		end)
		if #method.attrs == 0 then method.attrs = nil end

		self.methods:insert(method)
--DEBUG:print('reading method', methodIndex, require 'ext.tolua'(method))
	end

	self.attrs = table()
	readAttrs(blob, function(name, len)
		self.attrs:insert{
			name = name,
			data = blob:readString(len),
		}
	end)
	for _,attr in ipairs(self.attrs) do
		if attr.name == 'SourceFile' then
			-- attr.data is a uint16_t into the constants ...
			assert.len(attr.data, 2)
			local attrBlob = ReadBlob(attr.data)
			attr.data = nil
			attr.source = deepCopyIndex(attrBlob:readu2())
			attrBlob:assertDone()
		else
			error("TODO handle reading class attr "..tostring(attr.name))
		end
	end

	blob:assertDone()

	-- now that all consants have been deep-copied into where they are going, we dont really need the constants table anymore...
	self.constants = nil
end


-------------------------------- WRITING --------------------------------

-- hmm maybe 'toByteCode()' ?
function JavaASMClass:compile()
	--[[
	build constants fresh?  why not?
	cycle through all fields and all methods and their instructions
	accumulate unique constants
	store them as string binary blobs here per constant
	then do string compare to test uniqueness
	--]]
	local constants = table()

-- overwrite mind you ...
-- but here I rebuild them anyways so
-- TODO in the read phase, 'constants' is read as raw blobs
-- but then decoded to tables of indexed-references
-- and last is replaced by deep copy of tables
-- Here, 'constants' will be the just the raw blobs
-- so maybe I need dif names for each pass? 'constantBlobs', 'constantRefs', 'constants' ? maybe change that later.
self.constants = constants

	-- these methods are for compressing unique constants
	-- and for replacing deep-copies with *Index constant-table-reference fields

	-- 1) converts from deep copy trees to constant index refs
	-- 2) serializes into a blob
	-- 3) checks for uniqueness, returns previous index if not unique, adds if it is.
	local function addConst(const)
		local constBlob = WriteBlob()

		local tagname

		if type(const) == 'string' then	-- lua string == utf8string constant
			tagname = 'utf8string'
			constBlob:writeu1(1)	-- utf8string
			constBlob:writeu2(#const)
			constBlob:writeString(const)
		else
			assert.type(const, 'table')
			tagname = const.tag
			if const.tag == 'class' then
				constBlob:writeu1(7)
assert.type(const.name, 'string')
				constBlob:writeu2(addConst(const.name))	-- utf8string
			elseif const.tag == 'fieldRef' then
				constBlob:writeu1(9)
assert.eq(const.class.tag, 'class')
				constBlob:writeu2(addConst(const.class))
assert.eq(const.nameAndType.tag, 'nameAndType')
				constBlob:writeu2(addConst(const.nameAndType))
			elseif const.tag == 'methodRef' then
				constBlob:writeu1(10)
assert.eq(const.class.tag, 'class')
				constBlob:writeu2(addConst(const.class))
assert.eq(const.nameAndType.tag, 'nameAndType')
				constBlob:writeu2(addConst(const.nameAndType))
			elseif const.tag == 'interfaceMethodRef' then
				constBlob:writeu1(11)
assert.eq(const.class.tag, 'class')
				constBlob:writeu2(addConst(const.class))
assert.eq(const.nameAndType.tag, 'nameAndType')
				constBlob:writeu2(addConst(const.nameAndType))
			elseif const.tag == 'string' then
				constBlob:writeu1(8)
assert.type(const.value, 'string')
				constBlob:writeu2(addConst(const.value))	-- utf8string
			elseif const.tag == 'int' then
				constBlob:writeu1(3)
				constBlob:write('jint', const.value)
			elseif const.tag == 'float' then
				constBlob:writeu1(4)
				constBlob:write('jfloat', const.value)
			elseif const.tag == 'long' then
				constBlob:writeu1(5)
				constBlob:write('jlong', const.value)
			elseif const.tag == 'double' then
				constBlob:writeu1(6)
				constBlob:write('jdouble', const.value)
			elseif const.tag == 'nameAndType' then
				constBlob:writeu1(12)
assert.type(const.name, 'string')
				constBlob:writeu2(addConst(const.name))	-- utf8string
assert.type(const.sig, 'string')
				constBlob:writeu2(addConst(const.sig))	-- utf8string
			elseif const.tag == 'methodHandle' then
				constBlob:writeu1(15)
				local refKindIndex = assert.index({
					getField = 1,
					getStatic = 2,
					putField = 3,
					putStatic = 4,
					invokeVirtual = 5,
					invokeStatic = 6,
					invokeSpecial = 7,
					newInvokeSpecial = 8,
					invokeInterface = 9,
				}, assert.type(assert.index(const,' refKind'), 'string'))
				constBlob:writeu2(refKindIndex)
assert.type(const.reference, 'string')
				constBlob:writeu2(const.reference)	-- utf8string
			elseif const.tag == 'methodType' then
				constBlob:writeu1(16)
assert.type(const.sig, 'string')
				constBlob:writeu2(const.sig)	-- utf8string
			elseif const.tag == 'invokeDynamic' then
				constBlob:writeu1(18)
assert.type(const.bootstrapMethodAttr, 'string')		-- utf8string ... ???
				constBlob:writeu2(addConst(const.bootstrapMethodAttr))
assert.eq(const.nameAndType.tag, 'nameAndType')
				constBlob:writeu2(addConst(const.nameAndType))
			elseif const.tag == 'module' then
				constBlob:writeu1(19)
assert.type(const.name, 'string')
				constBlob:writeu2(addConst(const.name))	-- utf8string?
			elseif const.tag == 'package' then
				constBlob:writeu1(20)
assert.type(const.name, 'string')
				constBlob:writeu2(addConst(const.name))	-- utf8string?
			else
				error("idk how to encode const of tag "..tostring(const.tag))
			end
		end

		local constStr = constBlob:compile()
		for i,oconstStr in ipairs(constants) do
			if constStr == oconstStr then
				return i	-- already found
			end
		end

		constants:insert(constStr)
		local index = #constants

		-- add padding for 64bit constants
		if tagname == 'double' or tagname == 'long' then
			constants:insert(false)
		end

		return index
	end
	self.addConst = addConst

	local function addConstClass(name)
		return addConst{
			tag = 'class',
			name = assert.type(name, 'string'),
		}
	end
	self.addConstClass = addConstClass

	-- opposite of readAttrs
	local function writeAttrs(attrs, b)
		if not attrs then
			return b:writeu2(0)
		end
		b:writeu2(#attrs)
		for _,attr in ipairs(attrs) do
			b:writeu2(attr.nameIndex)
			assert.type(attr.data, 'string')
			b:writeu4(#attr.data)
			b:writeString(attr.data)
		end
	end



	-- first we have to cycle everything and build constants.

	-- collect class constants
	self.thisClassIndex = addConstClass((assert.type(assert.index(self, 'thisClass'), 'string')))
	self.superClassIndex = addConstClass((assert.type(assert.index(self, 'superClass'), 'string')))
--	self.thisClass = nil	-- necessary to clear or nah?
--	self.superClass = nil

	if self.interfaces then
		for i=1,#self.interfaces do
			self.interfaces[i] = addConstClass(self.interfaces[i])
		end
	end

	if self.fields then
		for i,field in ipairs(self.fields) do
--DEBUG:print('writing field', i, require 'ext.tolua'(field))
			field.nameIndex = addConst(field.name)
			field.sigIndex = addConst(field.sig)

			-- convert field.value into field.attrs[]
			-- where each attr has {uint16_t name; string data;}
			field.attrs = table()
			if field.value then
				local attrBlob = WriteBlob()
				attrBlob:writeu2(addConst(field.value))

				field.attrs:insert{
					nameIndex = addConst'ConstantValue',
					data = attrBlob:compile(),
				}
			end

			--field.name = nil	-- necessary to clear or nah?
			--field.sig = nil
			--field.value = nil
		end
	end

	if self.methods then
		for i,method in ipairs(self.methods) do
--DEBUG:print('writing method', i, require 'ext.tolua'(method))
			method.nameIndex = addConst(method.name)
			method.sigIndex = addConst(method.sig)

			method.attrs = table()

			if method.code then
--DEBUG:io.stderr:write('determined class '..self.thisClass..' method '..method.name..' sig '..method.sig..'\n')
				local minStack = 0
				local maxStack = 0
				local curStack = 0

				local maxLocals = method.isStatic and 0 or 1
				local sig = sigStrToObj(method.sig)
				for i=2,#sig do
					local sigi = sig[i]
					if sigi == 'long' or sigi == 'double'  then
						maxLocals = maxLocals + 2
					else
						maxLocals = maxLocals + 1
					end
				end


				local insBlob = WriteBlob()
				for instrIndex,inst in ipairs(method.code) do
					local op = assert.index(opForInstName, inst[1])
					local instDesc = assert.index(instDescForOp, op)

					-- while we're here, track the stack level so we can auto set 'maxStack'
					if instDesc.stacksub then
						if type(instDesc.stacksub) == 'number' then
							curStack = curStack - instDesc.stacksub
						elseif type(instDesc.stacksub) == 'function' then
							curStack = instDesc.stacksub(inst, curStack)
						else
							error("idk how to handle stacksub type "..type(instDesc.stacksub))
						end
						minStack = math.min(minStack, curStack)
						if minStack < 0 then
							io.stderr:write('!!! WARNING !!! method '
								..method.name..' instruction #'..instrIndex
								..': '..table.mapi(inst, function(x) return tostring(x) end):concat()
								..' stack underflow detected.\n')
						end
					end
					if instDesc.stackadd then
						if type(instDesc.stackadd) == 'number' then
							curStack = curStack + instDesc.stackadd
						elseif type(instDesc.stackadd) == 'function' then
							curStack = instDesc.stackadd(inst, curStack)
						else
							error("idk how to handle stackadd type "..type(instDesc.stackadd))
						end
						maxStack = math.max(maxStack, curStack)
					end
					if type(instDesc.maxLocals) == 'number' then
						maxLocals = math.max(maxLocals, instDesc.maxLocals)
					elseif type(instDesc.maxLocals) == 'function' then
						maxLocals = math.max(maxLocals, instDesc.maxLocals(inst))
					elseif type(instDesc.maxLocals) ~= 'nil' then
						error("idk how to handle maxLocals type "..type(instDesc.maxLocals))
					end

					insBlob:writeu1(op)
					local argDesc = instDesc.args
					if argDesc then
						if type(argDesc) == 'table' then
							for i,ctype in ipairs(argDesc) do
								insBlob:write(ctype, inst[i+1])
							end
						elseif type(argDesc) == 'function' then
							assert.index(instDesc, 'write')(inst, insBlob, self)
						else
							error('got unknown inst.args '..type(argDesc))
						end
					end
				end

				if not method.maxStack then
					method.maxStack = maxStack
io.stderr:write('determined class '..self.thisClass..' method '..method.name..' sig '..method.sig..' has maxStack='..maxStack..'\n')
				else
					-- NOTICE this can't handle labels so ...
					if method.maxStack ~= maxStack then
						io.stderr:write('!!! WARNING !!! '..method.name..' you set maxStack to '..method.maxStack..' but I calculated it as '..maxStack..'\n')
					end
				end

				if not method.maxLocals then
					method.maxLocals = maxLocals
io.stderr:write('determined class '..self.thisClass..' method '..method.name..' sig '..method.sig..' has maxLocals='..maxLocals..'\n')
				else
					-- NOTICE this can't handle labels so ...
					if method.maxLocals ~= maxLocals then
						io.stderr:write('!!! WARNING !!! '..method.name..' you set maxLocals to '..method.maxLocals..' but I calculated it as '..maxLocals..'\n')
					end
				end

				local cblob = WriteBlob()

--DEBUG:print('writing method stack locals', method.maxStack, method.maxLocals)
				cblob:writeu2(maxStack)
				cblob:writeu2(maxLocals)

				local insBlobData = insBlob:compile()
--DEBUG:print('writing method '..i..' insn blob '..#insBlobData)
--DEBUG:print(require 'ext.string'.hexdump(insBlobData))
				cblob:writeu4(#insBlobData)
				cblob:writeString(insBlobData)

				if not method.exceptions then
					cblob:writeu2(0)
				else
					cblob:writeu2(#method.exceptions)
					for _,ex in ipairs(method.exceptions) do
						cblob:writeu2(ex.startPC)
						cblob:writeu2(ex.endPC)
						cblob:writeu2(ex.handlerPC)
						cblob:writeu2(addConst(ex.catchType))
					end
				end

				local codeAttrs = method.codeAttrs or table()

				-- TODO handle StackMapTable here
				-- codeAttrs:insert(smAttr)

				if method.lineNos then
					local attrBlob = WriteBlob()
					attrBlob:writeu2(#method.lineNos)
					for _,lineNo in ipairs(method.lineNos) do
						attrBlob:writeu2(lineNo.startPC)
						attrBlob:writeu2(lineNo.lineNo)
					end
					codeAttrs:insert{
						nameIndex = addConst'LineNumberTable',
						data = attrBlob:compile(),
					}
				end

				writeAttrs(codeAttrs, cblob)

				-- TODO now add method.stackmap as attrs at the end of cblob

				local codeAttrData = cblob:compile()
--DEBUG:print('writing method '..i..' codeAttrData '..#codeAttrData)
--DEBUG:print(require'ext.string'.hexdump(codeAttrData))
				method.attrs:insert{
					nameIndex = addConst'Code',
					data = codeAttrData,
				}
			end

			-- necessary to clear or nah?

			--for LineNumberTable:
			--method.lineNos = nil

			-- Code
			--method.code = nil
			--method.maxStack = nil
			--method.maxLocals = nil
			--method.exceptions = nil

			--method.name = nil
			--method.sig = nil
		end
	end

	if self.attrs then
		for _,attr in ipairs(self.attrs) do
			if attr.name == 'SourceFile' then
				local attrBlob = WriteBlob()
				attrBlob:writeu2(addConst(
					(assert.type(attr.source, 'string'))
				))
				attr.data = attrBlob:compile()
			else
				error('TODO handle writing class attr '..tostring(attr.name))
			end

			-- TODO index fields
			attr.nameIndex = addConst(attr.name)
			assert.index(attr, 'data')

			--attr.name = nil
		end
	end


	-- table-of-strings that I concat() at the end
	local blob = WriteBlob()
	blob:writeu4(0xcafebabe)
	blob:writeu4(self.version or 0x41)		-- version

	-- write out constants
	blob:writeu2(#constants+1)
	for i,const in ipairs(constants) do
		if type(const) == 'string' then
			blob:writeString(const)
		elseif const ~= false then
			error("unknown value in the constants table "..require 'ext.tolua'(const))
		end
	end

	blob:writeu2(getFlagsFromObj(self, classAccessFlags))

	blob:writeu2(self.thisClassIndex)
	blob:writeu2(self.superClassIndex)

	if not self.interfaces then
		blob:writeu2(0)
	else
		blob:writeu2(#self.interfaces)
		for _,interfaceClassIndex in ipairs(self.interfaces) do
			blob:writeu2(interfaceClassIndex)
		end
	end

	-- write out fields
	if not self.fields then
		blob:writeu2(0)
	else
		blob:writeu2(#self.fields)
		for i,field in ipairs(self.fields) do
--DEBUG:print('writing field refd', i, require 'ext.tolua'(field))
			blob:writeu2(getFlagsFromObj(field, fieldAccessFlags))
			blob:writeu2(field.nameIndex)
			blob:writeu2(field.sigIndex)
			writeAttrs(field.attrs, blob)
		end
	end

	-- write out methods
	if not self.methods then
		blob:writeu2(0)
	else
		blob:writeu2(#self.methods)
		for i,method in ipairs(self.methods) do
--DEBUG:print('writing method refd', i, require 'ext.tolua'(method))
			blob:writeu2(getFlagsFromObj(method, methodAccessFlags))
			blob:writeu2(method.nameIndex)
			blob:writeu2(method.sigIndex)
			writeAttrs(method.attrs, blob)
		end
	end

	writeAttrs(self.attrs, blob)

	-- no longer need constants
	self.constants = nil

	return blob.data:concat()
end

-- shorthand for env:_defineClass(self, ...)
function JavaASMClass:_defineClass(env, ...)
	return env:_defineClass(self, ...)
end

return JavaASMClass
