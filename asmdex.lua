--[[
https://source.android.com/docs/core/runtime/dex-format
https://source.android.com/docs/core/runtime/dalvik-bytecode
https://source.android.com/docs/core/runtime/instruction-formats
--]]
local ffi = require 'ffi'
local class = require 'ext.class'
local assert = require 'ext.assert'
local table = require 'ext.table'
local string = require 'ext.string'
local ReadBlob = require 'java.blob'.ReadBlob
local WriteBlob = require 'java.blob'.WriteBlob
local deepCopy = require 'java.util'.deepCopy
local setFlagsToObj = require 'java.util'.setFlagsToObj
local setFlagsToObj = require 'java.util'.setFlagsToObj
local classAccessFlags = require 'java.util'.nestedClassAccessFlags	-- dalvik's class access flags matches up with .class's nested-class access flags
local fieldAccessFlags = require 'java.util'.fieldAccessFlags
local methodAccessFlags = require 'java.util'.methodAccessFlags

local function instAddString(inst, stringIndex, asm)
	local str = asm.strings[1+stringIndex]
	if not str then
		inst:insert('!!! WARNING !!! OOB string '..stringIndex)
	else
		inst:insert(str)
	end
end
local function instAddType(inst, typeIndex, asm)
	local typ = asm.types[1+typeIndex]
	if not typ then
		inst:insert('!!! WARNING !!! OOB type '..typeIndex)
	else
		inst:insert(typ)	-- TODO hmmm how to represent types?
	end
end
local function instAddProto(inst, protoIndex, asm)
	local proto = asm.protos[1+protoIndex]
	if not proto then
		inst:insert('!!! WARNING !!! OOB proto '..protoIndex)
	else
		inst:insert(proto)
	end
end
local function instAddField(inst, fieldIndex, asm)
	local field = asm.fields[1+fieldIndex]
	if not field then
		-- TODO this is a placeholder, I'm getting bad instructions because of bad other things ...
		inst:insert('!!! WARNING !!! OOB field '..fieldIndex)
	else
		inst:insert(field.class)
		inst:insert(field.name)
		inst:insert(field.sig)
	end
end
local function instAddMethod(inst, methodIndex, asm)
	local method = asm.methods[1+methodIndex]
	if not method then
		-- TODO this is a placeholder, I'm getting bad instructions because of bad other things ...
		inst:insert('!!! WARNING !!! OOB method '..methodIndex)
	else
		inst:insert(method.class)
		inst:insert(method.name)
		inst:insert(method.sig)
	end
end
local function read10x(inst, hi, lo, blob, asm)
	inst:insert('0x'..bit.tohex(hi, 2))				-- NOTICE throws away hi
end
local function read12x(inst, hi, lo, blob, asm)
	inst:insert('v'..bit.tohex(bit.band(hi, 0xf), 1))
	inst:insert('v'..bit.tohex(bit.band(bit.rshift(hi, 4), 0xf), 1))
end
local function read11x(inst, hi, lo, blob, asm)
	inst:insert('v'..bit.tohex(hi, 2))
end
local function read11n(inst, hi, lo, blob, asm)
	inst:insert('v'..bit.tohex(bit.band(0xf, hi), 1))	-- A = reg (4 bits)
	inst:insert('0x'..bit.tohex(bit.band(0xf, bit.rshift(hi, 8)), 1))		-- B = signed 4 bit
end
local function read10t(inst, hi, lo, blob, asm)
	inst:insert('0x'..bit.tohex(hi, 2))					-- signed 8 bit branch offset
end

local function read22x(inst, hi, lo, blob, asm)
	inst:insert('v'..bit.tohex(hi, 2))
	inst:insert('v'..bit.tohex(blob:readu2(), 4))
end
local function read21s(inst, hi, lo, blob, asm)
	inst:insert('v'..bit.tohex(hi, 2))
	inst:insert('0x'..bit.tohex(blob:readu2(), 4))	-- signed
end
local function read21h(inst, hi, lo, blob, asm)
	inst:insert('v'..bit.tohex(hi, 2))
	inst:insert('0x'..bit.tohex(blob:readu2(), 4))
end
local function read21c_string(inst, hi, lo, blob, asm)
	inst:insert('v'..bit.tohex(hi, 2))
	instAddString(inst, blob:readu2(), asm)
end
local function read21c_type(inst, hi, lo, blob, asm)
	inst:insert('v'..bit.tohex(hi, 2))
	instAddType(inst, blob:readu2(), asm)
end
local function read21c_field(inst, hi, lo, blob, asm)
	inst:insert('v'..bit.tohex(hi, 2))
	instAddField(inst, blob:readu2(), asm)
end
local function read22c_type(inst, hi, lo, blob, asm)
	inst:insert('v'..bit.tohex(bit.band(hi, 0xf), 1))
	inst:insert('v'..bit.tohex(bit.band(bit.rshift(hi, 4), 0xf), 1))
	instAddType(inst, blob:readu2(), asm)
end
local function read22c_field(inst, hi, lo, blob, asm)
	inst:insert('v'..bit.tohex(bit.band(hi, 0xf), 1))
	inst:insert('v'..bit.tohex(bit.band(bit.rshift(hi, 4), 0xf), 1))
	instAddField(inst, blob:readu2(), asm)
end
local function read23x(inst, hi, lo, blob, asm)
	inst:insert('v'..bit.tohex(hi, 2))
	inst:insert('v'..bit.tohex(blob:readu1(), 2))	-- I'm sure I'm doign this wrong but it says vAA vBB vCC and that A is 8 bits and that the whole instruction reads 2 words, so *shrug* no sign of bitness of B or C
	inst:insert('v'..bit.tohex(blob:readu1(), 2))
end
local function read20t(inst, hi, lo, blob, asm)
	inst:insert('0x'..bit.tohex(blob:read'int16_t', 4))		-- signed
	inst:insert('0x'..bit.tohex(hi, 2))		-- NOTICE throws away hi
end
local function read22t(inst, hi, lo, blob, asm)
	inst:insert('v'..bit.tohex(bit.band(hi, 0xf), 1))
	inst:insert('v'..bit.tohex(bit.band(bit.rshift(hi, 4), 0xf), 1))
	inst:insert('0x'..bit.tohex(blob:read'int16_t', 4))		-- signed
end
local function read21t(inst, hi, lo, blob, asm)
	inst:insert('v'..bit.tohex(hi, 2))
	inst:insert('0x'..bit.tohex(blob:read'int16_t', 4))	-- signed
end
local function read22s(inst, hi, lo, blob, asm)
	inst:insert('v'..bit.tohex(bit.band(hi, 0xf), 1))
	inst:insert('v'..bit.tohex(bit.band(bit.rshift(hi, 4), 0xf), 1))
	inst:insert('0x'..bit.tohex(blob:read'int16_t', 4))	-- signed
end
local function read22b(inst, hi, lo, blob, asm)
	inst:insert('v'..bit.tohex(bit.band(hi, 0xf), 1))
	inst:insert('v'..bit.tohex(bit.band(bit.rshift(hi, 4), 0xf), 1))
	local C = blob:read'int16_t'				-- A is bits, B is 8 bits, C is 8 bits ... so C hi is unused? ... or C lo?
	inst:insert('0x'..bit.tohex(C, 4))
end
local function read21c_method(inst, hi, lo, blob, asm)
	inst:insert('0x'..bit.tohex( blob:readu2(), 4))	-- TODO
end
local function read21c_proto(inst, hi, lo, blob, asm)
	inst:insert('0x'..bit.tohex( blob:readu2(), 4))	-- TODO
end

local function read32x(inst, hi, lo, blob, asm)
	inst:insert('v'..bit.tohex(blob:readu2(), 4))
	inst:insert('v'..bit.tohex(blob:readu2(), 4))
	inst:insert('0x'..bit.tohex(hi, 2))	-- NOTICE throws away hi
end
local function read31i(inst, hi, lo, blob, asm)
	inst:insert('v'..bit.tohex(hi, 2))
	inst:insert('0x'..bit.tohex(blob:readu4(), 8))	-- signed ... will this be 4-byte aligned?
end
local function read31c_string(inst, hi, lo, blob, asm)
	inst:insert('v'..bit.tohex(hi, 2))
	instAddString(inst, blob:readu4(), asm)
end
local function read35c_type(inst, hi, lo, blob, asm)
	inst:insert('0x'..bit.tohex(bit.band(hi, 0xf), 1))	-- A = array size ... 4 bits ...

	local typeIndex = blob:readu2()	-- B = type

	-- C..G are 4 bits each, so 20 bits total, so one of them is top nibble of 'hi' and the rest are another uint16 ...
	inst:insert('v'..bit.tohex(bit.band(bit.rshift(hi, 4), 0xf), 1))

	local x = blob:readu2()
	inst:insert('v'..bit.tohex(bit.band(x, 0xf), 1))
	inst:insert('v'..bit.tohex(bit.band(bit.rshift(x, 4), 0xf), 1))
	inst:insert('v'..bit.tohex(bit.band(bit.rshift(x, 8), 0xf), 1))
	inst:insert('v'..bit.tohex(bit.band(bit.rshift(x, 12), 0xf), 1))

	-- wait, B goes last?
	instAddType(inst, typeIndex, asm)
	-- what other args for identifying types?
end
local function read35c_method(inst, hi, lo, blob, asm)
	inst:insert('0x'..bit.tohex(bit.band(hi, 0xf), 1))	-- A = array size ... 4 bits ...

	local methodIndex = blob:readu2()	-- B = method

	-- C..G are 4 bits each, so 20 bits total, so one of them is top nibble of 'hi' and the rest are another uint16 ...
	inst:insert('v'..bit.tohex(bit.band(bit.rshift(hi, 4), 0xf), 1))

	local x = blob:readu2()
	inst:insert('v'..bit.tohex(bit.band(x, 0xf), 1))
	inst:insert('v'..bit.tohex(bit.band(bit.rshift(x, 4), 0xf), 1))
	inst:insert('v'..bit.tohex(bit.band(bit.rshift(x, 8), 0xf), 1))
	inst:insert('v'..bit.tohex(bit.band(bit.rshift(x, 12), 0xf), 1))

	-- wait, B goes last?
	instAddMethod(inst, methodIndex, asm)
end
local function read3rc_type(inst, hi, lo, blob, asm)
	inst:insert('v'..bit.tohex(hi, 2))	-- A = array size and argument word count ... N = A + C - 1
	local typeIndex = blob:readu2()	-- B = type
	inst:insert('v'..bit.tohex(blob:readu2(), 4))				-- C = first arg register
	instAddType(inst, typeIndex, asm)
end
local function read3rc_method(inst, hi, lo, blob, asm)
	inst:insert('v'..bit.tohex(hi, 2))	-- A = array size and argument word count ... N = A + C - 1
	local methodIndex = blob:readu2()	-- B = method
	inst:insert('v'..bit.tohex(blob:readu2(), 4))				-- C = first arg register
	instAddMethod(inst, methodIndex, asm)
end
local function read31t(inst, hi, lo, blob, asm)
	inst:insert('v'..bit.tohex(hi, 2))
	inst:insert('0x'..bit.tohex(blob:read'int32_t', 8))	-- signed branch offset to table data pseudo-instruction
end
local function read30t(inst, hi, lo, blob, asm)
	inst:insert('0x'..bit.tohex(blob:read'int32_t', 8))	-- signed
	inst:insert('0x'..bit.tohex(hi, 2))	-- NOTICE hi gets thrown away
end
local function read35c_callsite(inst, hi, lo, blob, asm)
	-- TODO
	inst:insert('0x'..bit.tohex(hi, 2))
	inst:insert('0x'..bit.tohex(blob:readu2(), 4))
	inst:insert('0x'..bit.tohex(blob:readu2(), 4))
end
local function read3rc_callsite(inst, hi, lo, blob, asm)
	-- TODO
	inst:insert('0x'..bit.tohex(hi, 2))
	inst:insert('0x'..bit.tohex(blob:readu2(), 4))
	inst:insert('0x'..bit.tohex(blob:readu2(), 4))
end

local function read45cc(inst, hi, lo, blob, asm)
	inst:insert('0x'..bit.tohex(bit.band(0xf, hi), 1))	-- arg word count 4 bits

	local methodIndex = blob:readu2()	-- B = method (16 bits)
	inst:insert('v'..bit.tohex(bit.rshift(bit.band(0xf, hi), 4), 1))	-- C = receiver 4 bits

	-- D E F G are arg registers
	local x = blob:readu2()
	inst:insert('v'..bit.tohex(bit.band(x, 0xf), 1))
	inst:insert('v'..bit.tohex(bit.band(bit.rshift(x, 4), 0xf), 1))
	inst:insert('v'..bit.tohex(bit.band(bit.rshift(x, 8), 0xf), 1))
	inst:insert('v'..bit.tohex(bit.band(bit.rshift(x, 12), 0xf), 1))

	local protoIndex = blob:readu2()	-- H = proto

	instAddMethod(inst, methodIndex, asm)
	instAddProto(inst, protoIndex, asm)
end
local function read4rcc(inst, hi, lo, blob, asm)
	inst:insert('0x'..bit.tohex(hi, 2))	-- arg word count 8 bits

	local methodIndex = blob:readu2()	-- B = method (16 bits)

	inst:insert('v'..bit.tohex(blob:readu2(), 4))	-- C = receiver 16 bits

	-- D - G = 16-bit register indexes?

	local protoIndex = blob:readu2()	-- H = proto

	-- I - N = more 16-bit register indexes?
	-- is there a number on these?
	--error"idk how to do this"

	instAddMethod(inst, methodIndex, asm)
	instAddProto(inst, protoIndex, asm)
end

local function read51l(inst, hi, lo, blob, asm)
	inst:insert('v'..bit.tohex(hi, 2))
	inst:insert('0x'..bit.tohex(blob:readu8(), 16))
end

local instDescForOp = {
	[0x00] = {name='nop', read=read10x},					-- 00 10x	nop	 	Waste cycles.	Note: Data-bearing pseudo-instructions are tagged with this opcode, in which case the high-order byte of the opcode unit indicates the nature of the data. See "packed-switch-payload Format", "sparse-switch-payload Format", and "fill-array-data-payload Format" below.
	[0x01] = {name='move', read=read12x},					-- 01 12x	move vA, vB	A: destination register (4 bits) B: source register (4 bits)	Move the contents of one non-object register to another.
	[0x02] = {name='move/from16', read=read22x},			-- 02 22x	move/from16 vAA, vBBBB	A: destination register (8 bits) B: source register (16 bits)	Move the contents of one non-object register to another.
	[0x03] = {name='move/16', read=read32x},				-- 03 32x	move/16 vAAAA, vBBBB	A: destination register (16 bits) B: source register (16 bits)	Move the contents of one non-object register to another.
	[0x04] = {name='move-wide', read=read12x},				-- 04 12x	move-wide vA, vB	A: destination register pair (4 bits) B: source register pair (4 bits)	Move the contents of one register-pair to another. Note: It is legal to move from vN to either vN-1 or vN+1, so implementations must arrange for both halves of a register pair to be read before anything is written.
	[0x05] = {name='move-wide/from16', read=read22x},		-- 05 22x	move-wide/from16 vAA, vBBBB	A: destination register pair (8 bits) B: source register pair (16 bits)	Move the contents of one register-pair to another. Note: Implementation considerations are the same as move-wide, above.
	[0x06] = {name='move-wide/16', read=read32x},			-- 06 32x	move-wide/16 vAAAA, vBBBB	A: destination register pair (16 bits) B: source register pair (16 bits)	Move the contents of one register-pair to another. Note: Implementation considerations are the same as move-wide, above.
	[0x07] = {name='move-object', read=read12x},			-- 07 12x	move-object vA, vB	A: destination register (4 bits) B: source register (4 bits)	Move the contents of one object-bearing register to another.
	[0x08] = {name='move-object/from16', read=read22x},		-- 08 22x	move-object/from16 vAA, vBBBB	A: destination register (8 bits) B: source register (16 bits)	Move the contents of one object-bearing register to another.
	[0x09] = {name='move-object/16', read=read32x},			-- 09 32x	move-object/16 vAAAA, vBBBB	A: destination register (16 bits) B: source register (16 bits)	Move the contents of one object-bearing register to another.
	[0x0a] = {name='move-result', read=read11x},			-- 0a 11x	move-result vAA	A: destination register (8 bits)	Move the single-word non-object result of the most recent invoke-kind into the indicated register. This must be done as the instruction immediately after an invoke-kind whose (single-word, non-object) result is not to be ignored; anywhere else is invalid.
	[0x0b] = {name='move-result-wide', read=read11x},			-- 0b 11x	move-result-wide vAA	A: destination register pair (8 bits)	Move the double-word result of the most recent invoke-kind into the indicated register pair. This must be done as the instruction immediately after an invoke-kind whose (double-word) result is not to be ignored; anywhere else is invalid.
	[0x0c] = {name='move-result-object', read=read11x},			-- 0c 11x	move-result-object vAA	A: destination register (8 bits)	Move the object result of the most recent invoke-kind into the indicated register. This must be done as the instruction immediately after an invoke-kind or filled-new-array whose (object) result is not to be ignored; anywhere else is invalid.
	[0x0d] = {name='move-exception', read=read11x},			-- 0d 11x	move-exception vAA	A: destination register (8 bits)	Save a just-caught exception into the given register. This must be the first instruction of any exception handler whose caught exception is not to be ignored, and this instruction must only ever occur as the first instruction of an exception handler; anywhere else is invalid.
	[0x0e] = {name='return-void', read=read10x},			-- 0e 10x	return-void	 	Return from a void method.
	[0x0f] = {name='return', read=read11x},			-- 0f 11x	return vAA	A: return value register (8 bits)	Return from a single-width (32-bit) non-object value-returning method.
	[0x10] = {name='return-wide', read=read11x},			-- 10 11x	return-wide vAA	A: return value register-pair (8 bits)	Return from a double-width (64-bit) value-returning method.
	[0x11] = {name='return-object', read=read11x},			-- 11 11x	return-object vAA	A: return value register (8 bits)	Return from an object-returning method.
	[0x12] = {name='const/4', read=read11n},			-- 12 11n	const/4 vA, #+B	A: destination register (4 bits) B: signed int (4 bits)	Move the given literal value (sign-extended to 32 bits) into the specified register.
	[0x13] = {name='const/16', read=read21s},			-- 13 21s	const/16 vAA, #+BBBB	A: destination register (8 bits) B: signed int (16 bits)	Move the given literal value (sign-extended to 32 bits) into the specified register.
	[0x14] = {name='const', read=read31i},			-- 14 31i	const vAA, #+BBBBBBBB	A: destination register (8 bits) B: arbitrary 32-bit constant	Move the given literal value into the specified register.
	[0x15] = {name='const/high16', read=read21h},			-- 15 21h	const/high16 vAA, #+BBBB0000	A: destination register (8 bits) B: signed int (16 bits)	Move the given literal value (right-zero-extended to 32 bits) into the specified register.
	[0x16] = {name='const-wide/16', read=read21s},			-- 16 21s	const-wide/16 vAA, #+BBBB	A: destination register (8 bits) B: signed int (16 bits)	Move the given literal value (sign-extended to 64 bits) into the specified register-pair.
	[0x17] = {name='const-wide/32', read=read31i},			-- 17 31i	const-wide/32 vAA, #+BBBBBBBB	A: destination register (8 bits) B: signed int (32 bits)	Move the given literal value (sign-extended to 64 bits) into the specified register-pair.
	[0x18] = {name='const-wide', read=read51l},			-- 18 51l	const-wide vAA, #+BBBBBBBBBBBBBBBB	A: destination register (8 bits) B: arbitrary double-width (64-bit) constant	Move the given literal value into the specified register-pair.
	[0x19] = {name='const-wide/high16', read=read21h},			-- 19 21h	const-wide/high16 vAA, #+BBBB000000000000	A: destination register (8 bits) B: signed int (16 bits)	Move the given literal value (right-zero-extended to 64 bits) into the specified register-pair.
	[0x1a] = {name='const-string', read=read21c_string},			-- 1a 21c	const-string vAA, string@BBBB	A: destination register (8 bits) B: string index	Move a reference to the string specified by the given index into the specified register.
	[0x1b] = {name='const-string/jumbo', read=read31c_string},			-- 1b 31c	const-string/jumbo vAA, string@BBBBBBBB	A: destination register (8 bits) B: string index	Move a reference to the string specified by the given index into the specified register.
	[0x1c] = {name='const-class', read=read21c_type},			-- 1c 21c	const-class vAA, type@BBBB	A: destination register (8 bits) B: type index	Move a reference to the class specified by the given index into the specified register. In the case where the indicated type is primitive, this will store a reference to the primitive type's degenerate class.
	[0x1d] = {name='monitor-enter', read=read11x},			-- 1d 11x	monitor-enter vAA	A: reference-bearing register (8 bits)	Acquire the monitor for the indicated object.
	[0x1e] = {name='monitor-exit', read=read11x},			-- 1e 11x	monitor-exit vAA	A: reference-bearing register (8 bits)	Release the monitor for the indicated object. Note: If this instruction needs to throw an exception, it must do so as if the pc has already advanced past the instruction. It may be useful to think of this as the instruction successfully executing (in a sense), and the exception getting thrown after the instruction but before the next one gets a chance to run. This definition makes it possible for a method to use a monitor cleanup catch-all (e.g., finally) block as the monitor cleanup for that block itself, as a way to handle the arbitrary exceptions that might get thrown due to the historical implementation of Thread.stop(), while still managing to have proper monitor hygiene.
	[0x1f] = {name='check-cast', read=read21c_type},			-- 1f 21c	check-cast vAA, type@BBBB	A: reference-bearing register (8 bits) B: type index (16 bits)	Throw a ClassCastException if the reference in the given register cannot be cast to the indicated type. Note: Since A must always be a reference (and not a primitive value), this will necessarily fail at runtime (that is, it will throw an exception) if B refers to a primitive type.
	[0x20] = {name='instance-of', read=read22c_type},			-- 20 22c	instance-of vA, vB, type@CCCC	A: destination register (4 bits) B: reference-bearing register (4 bits) C: type index (16 bits)	Store in the given destination register 1 if the indicated reference is an instance of the given type, or 0 if not. Note: Since B must always be a reference (and not a primitive value), this will always result in 0 being stored if C refers to a primitive type.
	[0x21] = {name='array-length', read=read12x},			-- 21 12x	array-length vA, vB	A: destination register (4 bits) B: array reference-bearing register (4 bits)	Store in the given destination register the length of the indicated array, in entries
	[0x22] = {name='new-instance', read=read21c_type},			-- 22 21c	new-instance vAA, type@BBBB	A: destination register (8 bits) B: type index	Construct a new instance of the indicated type, storing a reference to it in the destination. The type must refer to a non-array class.
	[0x23] = {name='new-array', read=read22c_type},			-- 23 22c	new-array vA, vB, type@CCCC	A: destination register (4 bits) B: size register C: type index	Construct a new array of the indicated type and size. The type must be an array type.
	[0x24] = {name='filled-new-array', read=read35c_type},			-- 24 35c	filled-new-array {vC, vD, vE, vF, vG}, type@BBBB	A: array size and argument word count (4 bits) B: type index (16 bits) C..G: argument registers (4 bits each)	Construct an array of the given type and size, filling it with the supplied contents. The type must be an array type. The array's contents must be single-word (that is, no arrays of long or double, but reference types are acceptable). The constructed instance is stored as a "result" in the same way that the method invocation instructions store their results, so the constructed instance must be moved to a register with an immediately subsequent move-result-object instruction (if it is to be used).
	[0x25] = {name='filled-new-array/range', read=read3rc_type},			-- 25 3rc	filled-new-array/range {vCCCC .. vNNNN}, type@BBBB	A: array size and argument word count (8 bits) B: type index (16 bits) C: first argument register (16 bits) N = A + C - 1	Construct an array of the given type and size, filling it with the supplied contents. Clarifications and restrictions are the same as filled-new-array, described above.
	[0x26] = {name='fill-array-data', read=read31t},			-- 26 31t	fill-array-data vAA, +BBBBBBBB (with supplemental data as specified below in "fill-array-data-payload Format")	A: array reference (8 bits) B: signed "branch" offset to table data pseudo-instruction (32 bits)	Fill the given array with the indicated data. The reference must be to an array of primitives, and the data table must match it in type and must contain no more elements than will fit in the array. That is, the array may be larger than the table, and if so, only the initial elements of the array are set, leaving the remainder alone.
	[0x27] = {name='throw', read=read11x},			-- 27 11x	throw vAA	A: exception-bearing register (8 bits) Throw the indicated exception.
	[0x28] = {name='goto', read=read10t},			-- 28 10t	goto +AA	A: signed branch offset (8 bits)	Unconditionally jump to the indicated instruction. Note: The branch offset must not be 0. (A spin loop may be legally constructed either with goto/32 or by including a nop as a target before the branch.)
	[0x29] = {name='goto/16', read=read20t},			-- 29 20t	goto/16 +AAAA	A: signed branch offset (16 bits) Unconditionally jump to the indicated instruction. Note: The branch offset must not be 0. (A spin loop may be legally constructed either with goto/32 or by including a nop as a target before the branch.)
	[0x2a] = {name='goto/32', read=read30t},			-- 2a 30t	goto/32 +AAAAAAAA	A: signed branch offset (32 bits) Unconditionally jump to the indicated instruction.
	[0x2b] = {name='packed-switch', read=read31t},			-- 2b 31t	packed-switch vAA, +BBBBBBBB (with supplemental data as specified below in "packed-switch-payload Format")	A: register to test B: signed "branch" offset to table data pseudo-instruction (32 bits)	Jump to a new instruction based on the value in the given register, using a table of offsets corresponding to each value in a particular integral range, or fall through to the next instruction if there is no match.
	[0x2c] = {name='sparse-switch', read=read31t},			-- 2c 31t	sparse-switch vAA, +BBBBBBBB (with supplemental data as specified below in "sparse-switch-payload Format")	A: register to test B: signed "branch" offset to table data pseudo-instruction (32 bits)	Jump to a new instruction based on the value in the given register, using an ordered table of value-offset pairs, or fall through to the next instruction if there is no match.
	[0x2d] = {name='cmpl-float', read=read23x},			-- 2d 23x	cmpl-float vAA, vBB, vCC
	[0x2e] = {name='cmpg-float', read=read23x},			-- 2e 23x	cmpg-float vAA, vBB, vCC
	[0x2f] = {name='cmpl-double', read=read23x},			-- 2f 23x	cmpl-double vAA, vBB, vCC
	[0x30] = {name='cmpg-double', read=read23x},			-- 30 23x	cmpg-double vAA, vBB, vCC
	[0x31] = {name='cmp-long', read=read23x},			-- 31 23x	cmp-long vAA, vBB, vCC		A: destination register (8 bits) B: first source register or pair C: second source register or pair	Perform the indicated floating point or long comparison, setting a to 0 if b == c, 1 if b > c, or -1 if b < c. The "bias" listed for the floating point operations indicates how NaN comparisons are treated: "gt bias" instructions return 1 for NaN comparisons, and "lt bias" instructions return -1. For example, to check to see if floating point x < y it is advisable to use cmpg-float; a result of -1 indicates that the test was true, and the other values indicate it was false either due to a valid comparison or because one of the values was NaN.
	[0x32] = {name='if-eq', read=read22t},			-- 32 22t	if-eq vA, vB, +CCCC
	[0x33] = {name='if-ne', read=read22t},			-- 33 22t	if-ne vA, vB, +CCCC
	[0x34] = {name='if-lt', read=read22t},			-- 34 22t	if-lt vA, vB, +CCCC
	[0x35] = {name='if-ge', read=read22t},			-- 35 22t	if-ge vA, vB, +CCCC
	[0x36] = {name='if-gt', read=read22t},			-- 36 22t	if-gt vA, vB, +CCCC
	[0x37] = {name='if-le', read=read22t},			-- 37 22t	if-le vA, vB, +CCCC A: first register to test (4 bits) B: second register to test (4 bits) C: signed branch offset (16 bits)	Branch to the given destination if the given two registers' values compare as specified. Note: The branch offset must not be 0. (A spin loop may be legally constructed either by branching around a backward goto or by including a nop as a target before the branch.)
	[0x38] = {name='if-eqz', read=read21t},			-- 38 21t	if-eqz vAA, +BBBB
	[0x39] = {name='if-nez', read=read21t},			-- 39 21t	if-nez vAA, +BBBB
	[0x3a] = {name='if-ltz', read=read21t},			-- 3a 21t	if-ltz vAA, +BBBB
	[0x3b] = {name='if-gez', read=read21t},			-- 3b 21t	if-gez vAA, +BBBB
	[0x3c] = {name='if-gtz', read=read21t},			-- 3c 21t	if-gtz vAA, +BBBB
	[0x3d] = {name='if-lez', read=read21t},			-- 3d 21t	if-lez vAA, +BBBB A: register to test (8 bits) B: signed branch offset (16 bits)	Branch to the given destination if the given register's value compares with 0 as specified. Note: The branch offset must not be 0. (A spin loop may be legally constructed either by branching around a backward goto or by including a nop as a target before the branch.)
	[0x3e] = {name='unused', read=read10x},			-- 3e 10x	unused	 	unused
	[0x3f] = {name='unused', read=read10x},			-- 3f 10x	unused	 	unused
	[0x40] = {name='unused', read=read10x},			-- 40 10x	unused	 	unused
	[0x41] = {name='unused', read=read10x},			-- 41 10x	unused	 	unused
	[0x42] = {name='unused', read=read10x},			-- 42 10x	unused	 	unused
	[0x43] = {name='unused', read=read10x},			-- 43 10x	unused	 	unused
	[0x44] = {name='aget', read=read23x},			-- 44 23x	aget vAA, vBB, vCC
	[0x45] = {name='aget-wide', read=read23x},			-- 45 23x	aget-wide vAA, vBB, vCC
	[0x46] = {name='aget-object', read=read23x},			-- 46 23x	aget-object vAA, vBB, vCC
	[0x47] = {name='aget-boolean', read=read23x},			-- 47 23x	aget-boolean vAA, vBB, vCC
	[0x48] = {name='aget-byte', read=read23x},			-- 48 23x	aget-byte vAA, vBB, vCC
	[0x49] = {name='aget-char', read=read23x},			-- 49 23x	aget-char vAA, vBB, vCC
	[0x4a] = {name='aget-short', read=read23x},			-- 4a 23x	aget-short vAA, vBB, vCC
	[0x4b] = {name='aput', read=read23x},			-- 4b 23x	aput vAA, vBB, vCC
	[0x4c] = {name='aput-wide', read=read23x},			-- 4c 23x	aput-wide vAA, vBB, vCC
	[0x4d] = {name='aput-object', read=read23x},			-- 4d 23x	aput-object vAA, vBB, vCC
	[0x4e] = {name='aput-boolean', read=read23x},			-- 4e 23x	aput-boolean vAA, vBB, vCC
	[0x4f] = {name='aput-byte', read=read23x},			-- 4f 23x	aput-byte vAA, vBB, vCC
	[0x50] = {name='aput-char', read=read23x},			-- 50 23x	aput-char vAA, vBB, vCC
	[0x51] = {name='aput-short', read=read23x},			-- 51 23x	aput-short vAA, vBB, vCC	A: value register or pair; may be source or dest (8 bits) B: array register (8 bits) C: index register (8 bits)	Perform the identified array operation at the identified index of the given array, loading or storing into the value register.
	[0x52] = {name='iget', read=read22c_field},			-- 52 22c	iget vA, vB, field@CCCC
	[0x53] = {name='iget-wide', read=read22c_field},			-- 53 22c	iget-wide vA, vB, field@CCCC
	[0x54] = {name='iget-object', read=read22c_field},			-- 54 22c	iget-object vA, vB, field@CCCC
	[0x55] = {name='iget-boolean', read=read22c_field},			-- 55 22c	iget-boolean vA, vB, field@CCCC
	[0x56] = {name='iget-byte', read=read22c_field},			-- 56 22c	iget-byte vA, vB, field@CCCC
	[0x57] = {name='iget-char', read=read22c_field},			-- 57 22c	iget-char vA, vB, field@CCCC
	[0x58] = {name='iget-short', read=read22c_field},			-- 58 22c	iget-short vA, vB, field@CCCC
	[0x59] = {name='iput', read=read22c_field},			-- 59 22c	iput vA, vB, field@CCCC
	[0x5a] = {name='iput-wide', read=read22c_field},			-- 5a 22c	iput-wide vA, vB, field@CCCC
	[0x5b] = {name='iput-object', read=read22c_field},			-- 5b 22c	iput-object vA, vB, field@CCCC
	[0x5c] = {name='iput-boolean', read=read22c_field},			-- 5c 22c	iput-boolean vA, vB, field@CCCC
	[0x5d] = {name='iput-byte', read=read22c_field},			-- 5d 22c	iput-byte vA, vB, field@CCCC
	[0x5e] = {name='iput-char', read=read22c_field},			-- 5e 22c	iput-char vA, vB, field@CCCC
	[0x5f] = {name='iput-short', read=read22c_field},			-- 5f 22c	iput-short vA, vB, field@CCCC	A: value register or pair; may be source or dest (4 bits) B: object register (4 bits) C: instance field reference index (16 bits)	Perform the identified object instance field operation with the identified field, loading or storing into the value register. Note: These opcodes are reasonable candidates for static linking, altering the field argument to be a more direct offset.
	[0x60] = {name='sget', read=read21c_field},			-- 60 21c	sget vAA, field@BBBB
	[0x61] = {name='sget-wide', read=read21c_field},			-- 61 21c	sget-wide vAA, field@BBBB
	[0x62] = {name='sget-object', read=read21c_field},			-- 62 21c	sget-object vAA, field@BBBB
	[0x63] = {name='sget-boolean', read=read21c_field},			-- 63 21c	sget-boolean vAA, field@BBBB
	[0x64] = {name='sget-byte', read=read21c_field},			-- 64 21c	sget-byte vAA, field@BBBB
	[0x65] = {name='sget-char', read=read21c_field},			-- 65 21c	sget-char vAA, field@BBBB
	[0x66] = {name='sget-short', read=read21c_field},			-- 66 21c	sget-short vAA, field@BBBB
	[0x67] = {name='sput', read=read21c_field},			-- 67 21c	sput vAA, field@BBBB
	[0x68] = {name='sput-wide', read=read21c_field},			-- 68 21c	sput-wide vAA, field@BBBB
	[0x69] = {name='sput-object', read=read21c_field},			-- 69 21c	sput-object vAA, field@BBBB
	[0x6a] = {name='sput-boolean', read=read21c_field},			-- 6a 21c	sput-boolean vAA, field@BBBB
	[0x6b] = {name='sput-byte', read=read21c_field},			-- 6b 21c	sput-byte vAA, field@BBBB
	[0x6c] = {name='sput-char', read=read21c_field},			-- 6c 21c	sput-char vAA, field@BBBB
	[0x6d] = {name='sput-short', read=read21c_field},			-- 6d 21c	sput-short vAA, field@BBBB	A: value register or pair; may be source or dest (8 bits) B: static field reference index (16 bits)	Perform the identified object static field operation with the identified static field, loading or storing into the value register. Note: These opcodes are reasonable candidates for static linking, altering the field argument to be a more direct offset.
	[0x6e] = {name='invoke-virtual', read=read35c_method},			-- 6e 35c	invoke-virtual {vC, vD, vE, vF, vG}, meth@BBBB
	[0x6f] = {name='invoke-super', read=read35c_method},			-- 6f 35c	invoke-super {vC, vD, vE, vF, vG}, meth@BBBB
	[0x70] = {name='invoke-direct', read=read35c_method},			-- 70 35c	invoke-direct {vC, vD, vE, vF, vG}, meth@BBBB
	[0x71] = {name='invoke-static', read=read35c_method},			-- 71 35c	invoke-static {vC, vD, vE, vF, vG}, meth@BBBB
	[0x72] = {name='invoke-interface', read=read35c_method},			-- 72 35c	invoke-interface {vC, vD, vE, vF, vG}, meth@BBBB	A: argument word count (4 bits) B: method reference index (16 bits) C..G: argument registers (4 bits each)	Call the indicated method. The result (if any) may be stored with an appropriate move-result* variant as the immediately subsequent instruction. invoke-virtual is used to invoke a normal virtual method which is a method that isn't static, private or a constructor. When the method_id references a method of a non-interface class, invoke-super is used to invoke the closest superclass's virtual method (as opposed to the one with the same method_id in the calling class). The same method restrictions hold as for invoke-virtual. In Dex files version 037 or later, if the method_id refers to an interface method, invoke-super is used to invoke the most specific, non-overridden version of that method defined on that interface. The same method restrictions hold as for invoke-virtual. In Dex files prior to version 037, having an interface method_id is illegal and undefined. invoke-direct is used to invoke a non-static direct method (that is, an instance method that is by its nature non-overridable, namely either a private instance method or a constructor). invoke-static is used to invoke a static method (which is always considered a direct method). invoke-interface is used to invoke an interface method, that is, on an object whose concrete class isn't known, using a method_id that refers to an interface. Note: These opcodes are reasonable candidates for static linking, altering the method argument to be a more direct offset (or pair thereof).
	[0x73] = {name='unused', read=read10x},			-- 73 10x	unused		unused
	[0x74] = {name='invoke-virtual/range', read=read3rc_method},			-- 74 3rc	invoke-virtual/range {vCCCC .. vNNNN}, meth@BBBB
	[0x75] = {name='invoke-super/range', read=read3rc_method},			-- 75 3rc	invoke-super/range {vCCCC .. vNNNN}, meth@BBBB
	[0x76] = {name='invoke-direct/range', read=read3rc_method},			-- 76 3rc	invoke-direct/range {vCCCC .. vNNNN}, meth@BBBB
	[0x77] = {name='invoke-static/range', read=read3rc_method},			-- 77 3rc	invoke-static/range {vCCCC .. vNNNN}, meth@BBBB
	[0x78] = {name='invoke-interface/range', read=read3rc_method},			-- 78 3rc	invoke-interface/range {vCCCC .. vNNNN}, meth@BBBB	A: argument word count (8 bits) B: method reference index (16 bits) C: first argument register (16 bits) N = A + C - 1	Call the indicated method. See first invoke-kind description above for details, caveats, and suggestions.
	[0x79] = {name='unused', read=read10x},			-- 79 10x	unused		unused
	[0x7a] = {name='unused', read=read10x},			-- 7a 10x	unused		unused
	[0x7b] = {name='neg-int', read=read12x},			-- 7b 12x	neg-int vA, vB
	[0x7c] = {name='not-int', read=read12x},			-- 7c 12x	not-int vA, vB
	[0x7d] = {name='neg-long', read=read12x},			-- 7d 12x	neg-long vA, vB
	[0x7e] = {name='not-long', read=read12x},			-- 7e 12x	not-long vA, vB
	[0x7f] = {name='neg-float', read=read12x},			-- 7f 12x	neg-float vA, vB
	[0x80] = {name='neg-double', read=read12x},			-- 80 12x	neg-double vA, vB
	[0x81] = {name='int-to-long', read=read12x},			-- 81 12x	int-to-long vA, vB
	[0x82] = {name='int-to-float', read=read12x},			-- 82 12x	int-to-float vA, vB
	[0x83] = {name='int-to-double', read=read12x},			-- 83 12x	int-to-double vA, vB
	[0x84] = {name='long-to-int', read=read12x},			-- 84 12x	long-to-int vA, vB
	[0x85] = {name='long-to-float', read=read12x},			-- 85 12x	long-to-float vA, vB
	[0x86] = {name='long-to-double', read=read12x},			-- 86 12x	long-to-double vA, vB
	[0x87] = {name='float-to-int', read=read12x},			-- 87 12x	float-to-int vA, vB
	[0x88] = {name='float-to-long', read=read12x},			-- 88 12x	float-to-long vA, vB
	[0x89] = {name='float-to-double', read=read12x},			-- 89 12x	float-to-double vA, vB
	[0x8a] = {name='double-to-int', read=read12x},			-- 8a 12x	double-to-int vA, vB
	[0x8b] = {name='double-to-long', read=read12x},			-- 8b 12x	double-to-long vA, vB
	[0x8c] = {name='double-to-float', read=read12x},			-- 8c 12x	double-to-float vA, vB
	[0x8d] = {name='int-to-byte', read=read12x},			-- 8d 12x	int-to-byte vA, vB
	[0x8e] = {name='int-to-char', read=read12x},			-- 8e 12x	int-to-char vA, vB
	[0x8f] = {name='int-to-short', read=read12x},			-- 8f 12x	int-to-short vA, vB	A: destination register or pair (4 bits) B: source register or pair (4 bits)	Perform the identified unary operation on the source register, storing the result in the destination register.
	[0x90] = {name='add-int', read=read23x},			-- 90 23x	add-int vAA, vBB, vCC
	[0x91] = {name='sub-int', read=read23x},			-- 91 23x	sub-int vAA, vBB, vCC
	[0x92] = {name='mul-int', read=read23x},			-- 92 23x	mul-int vAA, vBB, vCC
	[0x93] = {name='div-int', read=read23x},			-- 93 23x	div-int vAA, vBB, vCC
	[0x94] = {name='rem-int', read=read23x},			-- 94 23x	rem-int vAA, vBB, vCC
	[0x95] = {name='and-int', read=read23x},			-- 95 23x	and-int vAA, vBB, vCC
	[0x96] = {name='or-int', read=read23x},			-- 96 23x	or-int vAA, vBB, vCC
	[0x97] = {name='xor-int', read=read23x},			-- 97 23x	xor-int vAA, vBB, vCC
	[0x98] = {name='shl-int', read=read23x},			-- 98 23x	shl-int vAA, vBB, vCC
	[0x99] = {name='shr-int', read=read23x},			-- 99 23x	shr-int vAA, vBB, vCC
	[0x9a] = {name='ushr-int', read=read23x},			-- 9a 23x	ushr-int vAA, vBB, vCC
	[0x9b] = {name='add-long', read=read23x},			-- 9b 23x	add-long vAA, vBB, vCC
	[0x9c] = {name='sub-long', read=read23x},			-- 9c 23x	sub-long vAA, vBB, vCC
	[0x9d] = {name='mul-long', read=read23x},			-- 9d 23x	mul-long vAA, vBB, vCC
	[0x9e] = {name='div-long', read=read23x},			-- 9e 23x	div-long vAA, vBB, vCC
	[0x9f] = {name='rem-long', read=read23x},			-- 9f 23x	rem-long vAA, vBB, vCC
	[0xa0] = {name='and-long', read=read23x},			-- a0 23x	and-long vAA, vBB, vCC
	[0xa1] = {name='or-long', read=read23x},			-- a1 23x	or-long vAA, vBB, vCC
	[0xa2] = {name='xor-long', read=read23x},			-- a2 23x	xor-long vAA, vBB, vCC
	[0xa3] = {name='shl-long', read=read23x},			-- a3 23x	shl-long vAA, vBB, vCC
	[0xa4] = {name='shr-long', read=read23x},			-- a4 23x	shr-long vAA, vBB, vCC
	[0xa5] = {name='ushr-long', read=read23x},			-- a5 23x	ushr-long vAA, vBB, vCC
	[0xa6] = {name='add-float', read=read23x},			-- a6 23x	add-float vAA, vBB, vCC
	[0xa7] = {name='sub-float', read=read23x},			-- a7 23x	sub-float vAA, vBB, vCC
	[0xa8] = {name='mul-float', read=read23x},			-- a8 23x	mul-float vAA, vBB, vCC
	[0xa9] = {name='div-float', read=read23x},			-- a9 23x	div-float vAA, vBB, vCC
	[0xaa] = {name='rem-float', read=read23x},			-- aa 23x	rem-float vAA, vBB, vCC
	[0xab] = {name='add-double', read=read23x},			-- ab 23x	add-double vAA, vBB, vCC
	[0xac] = {name='sub-double', read=read23x},			-- ac 23x	sub-double vAA, vBB, vCC
	[0xad] = {name='mul-double', read=read23x},			-- ad 23x	mul-double vAA, vBB, vCC
	[0xae] = {name='div-double', read=read23x},			-- ae 23x	div-double vAA, vBB, vCC
	[0xaf] = {name='rem-double', read=read23x},			-- af 23x	rem-double vAA, vBB, vCC	A: destination register or pair (8 bits) B: first source register or pair (8 bits) C: second source register or pair (8 bits)	Perform the identified binary operation on the two source registers, storing the result in the destination register. Note: Contrary to other -long mathematical operations (which take register pairs for both their first and their second source), shl-long, shr-long, and ushr-long take a register pair for their first source (the value to be shifted), but a single register for their second source (the shifting distance).
	[0xb0] = {name='add-int/2addr', read=read12x},			-- b0 12x	add-int/2addr vA, vB
	[0xb1] = {name='sub-int/2addr', read=read12x},			-- b1 12x	sub-int/2addr vA, vB
	[0xb2] = {name='mul-int/2addr', read=read12x},			-- b2 12x	mul-int/2addr vA, vB
	[0xb3] = {name='div-int/2addr', read=read12x},			-- b3 12x	div-int/2addr vA, vB
	[0xb4] = {name='rem-int/2addr', read=read12x},			-- b4 12x	rem-int/2addr vA, vB
	[0xb5] = {name='and-int/2addr', read=read12x},			-- b5 12x	and-int/2addr vA, vB
	[0xb6] = {name='or-int/2addr', read=read12x},			-- b6 12x	or-int/2addr vA, vB
	[0xb7] = {name='xor-int/2addr', read=read12x},			-- b7 12x	xor-int/2addr vA, vB
	[0xb8] = {name='shl-int/2addr', read=read12x},			-- b8 12x	shl-int/2addr vA, vB
	[0xb9] = {name='shr-int/2addr', read=read12x},			-- b9 12x	shr-int/2addr vA, vB
	[0xba] = {name='ushr-int/2addr', read=read12x},			-- ba 12x	ushr-int/2addr vA, vB
	[0xbb] = {name='add-long/2addr', read=read12x},			-- bb 12x	add-long/2addr vA, vB
	[0xbc] = {name='sub-long/2addr', read=read12x},			-- bc 12x	sub-long/2addr vA, vB
	[0xbd] = {name='mul-long/2addr', read=read12x},			-- bd 12x	mul-long/2addr vA, vB
	[0xbe] = {name='div-long/2addr', read=read12x},			-- be 12x	div-long/2addr vA, vB
	[0xbf] = {name='rem-long/2addr', read=read12x},			-- bf 12x	rem-long/2addr vA, vB
	[0xc0] = {name='and-long/2addr', read=read12x},			-- c0 12x	and-long/2addr vA, vB
	[0xc1] = {name='or-long/2addr', read=read12x},			-- c1 12x	or-long/2addr vA, vB
	[0xc2] = {name='xor-long/2addr', read=read12x},			-- c2 12x	xor-long/2addr vA, vB
	[0xc3] = {name='shl-long/2addr', read=read12x},			-- c3 12x	shl-long/2addr vA, vB
	[0xc4] = {name='shr-long/2addr', read=read12x},			-- c4 12x	shr-long/2addr vA, vB
	[0xc5] = {name='ushr-long/2addr', read=read12x},			-- c5 12x	ushr-long/2addr vA, vB
	[0xc6] = {name='add-float/2addr', read=read12x},			-- c6 12x	add-float/2addr vA, vB
	[0xc7] = {name='sub-float/2addr', read=read12x},			-- c7 12x	sub-float/2addr vA, vB
	[0xc8] = {name='mul-float/2addr', read=read12x},			-- c8 12x	mul-float/2addr vA, vB
	[0xc9] = {name='div-float/2addr', read=read12x},			-- c9 12x	div-float/2addr vA, vB
	[0xca] = {name='rem-float/2addr', read=read12x},			-- ca 12x	rem-float/2addr vA, vB
	[0xcb] = {name='add-double/2addr', read=read12x},			-- cb 12x	add-double/2addr vA, vB
	[0xcc] = {name='sub-double/2addr', read=read12x},			-- cc 12x	sub-double/2addr vA, vB
	[0xcd] = {name='mul-double/2addr', read=read12x},			-- cd 12x	mul-double/2addr vA, vB
	[0xce] = {name='div-double/2addr', read=read12x},			-- ce 12x	div-double/2addr vA, vB
	[0xcf] = {name='rem-double/2addr', read=read12x},			-- cf 12x	rem-double/2addr vA, vB	A: destination and first source register or pair (4 bits) B: second source register or pair (4 bits)	Perform the identified binary operation on the two source registers, storing the result in the first source register. Note: Contrary to other -long/2addr mathematical operations (which take register pairs for both their destination/first source and their second source), shl-long/2addr, shr-long/2addr, and ushr-long/2addr take a register pair for their destination/first source (the value to be shifted), but a single register for their second source (the shifting distance).
	[0xd0] = {name='add-int/lit16', read=read22s},			-- d0 22s	add-int/lit16 vA, vB, #+CCCC
	[0xd1] = {name='rsub-int', read=read22s},			-- d1 22s	rsub-int vA, vB, #+CCCC (reverse subtract)
	[0xd2] = {name='mul-int/lit16', read=read22s},			-- d2 22s	mul-int/lit16 vA, vB, #+CCCC
	[0xd3] = {name='div-int/lit16', read=read22s},			-- d3 22s	div-int/lit16 vA, vB, #+CCCC
	[0xd4] = {name='rem-int/lit16', read=read22s},			-- d4 22s	rem-int/lit16 vA, vB, #+CCCC
	[0xd5] = {name='and-int/lit16', read=read22s},			-- d5 22s	and-int/lit16 vA, vB, #+CCCC
	[0xd6] = {name='or-int/lit16', read=read22s},			-- d6 22s	or-int/lit16 vA, vB, #+CCCC
	[0xd7] = {name='xor-int/lit16', read=read22s},			-- d7 22s	xor-int/lit16 vA, vB, #+CCCC	A: destination register (4 bits) B: source register (4 bits) C: signed int constant (16 bits)	Perform the indicated binary op on the indicated register (first argument) and literal value (second argument), storing the result in the destination register. Note: rsub-int does not have a suffix since this version is the main opcode of its family. Also, see below for details on its semantics.
	[0xd8] = {name='add-int/lit8', read=read22b},			-- d8 22b	add-int/lit8 vAA, vBB, #+CC
	[0xd9] = {name='rsub-int/lit8', read=read22b},			-- d9 22b	rsub-int/lit8 vAA, vBB, #+CC
	[0xda] = {name='mul-int/lit8', read=read22b},			-- da 22b	mul-int/lit8 vAA, vBB, #+CC
	[0xdb] = {name='div-int/lit8', read=read22b},			-- db 22b	div-int/lit8 vAA, vBB, #+CC
	[0xdc] = {name='rem-int/lit8', read=read22b},			-- dc 22b	rem-int/lit8 vAA, vBB, #+CC
	[0xdd] = {name='and-int/lit8', read=read22b},			-- dd 22b	and-int/lit8 vAA, vBB, #+CC
	[0xde] = {name='or-int/lit8', read=read22b},			-- de 22b	or-int/lit8 vAA, vBB, #+CC
	[0xdf] = {name='xor-int/lit8', read=read22b},			-- df 22b	xor-int/lit8 vAA, vBB, #+CC
	[0xe0] = {name='shl-int/lit8', read=read22b},			-- e0 22b	shl-int/lit8 vAA, vBB, #+CC
	[0xe1] = {name='shr-int/lit8', read=read22b},			-- e1 22b	shr-int/lit8 vAA, vBB, #+CC
	[0xe2] = {name='ushr-int/lit8', read=read22b},			-- e2 22b	ushr-int/lit8 vAA, vBB, #+CC	A: destination register (8 bits) B: source register (8 bits) C: signed int constant (8 bits)	Perform the indicated binary op on the indicated register (first argument) and literal value (second argument), storing the result in the destination register. Note: See below for details on the semantics of rsub-int.
	[0xe3] = {name='unused', read=read10x},			-- e3 10x	unused	 	unused
	[0xe4] = {name='unused', read=read10x},			-- e4 10x	unused	 	unused
	[0xe5] = {name='unused', read=read10x},			-- e5 10x	unused	 	unused
	[0xe6] = {name='unused', read=read10x},			-- e6 10x	unused	 	unused
	[0xe7] = {name='unused', read=read10x},			-- e7 10x	unused	 	unused
	[0xe8] = {name='unused', read=read10x},			-- e8 10x	unused	 	unused
	[0xe9] = {name='unused', read=read10x},			-- e9 10x	unused	 	unused
	[0xea] = {name='unused', read=read10x},			-- ea 10x	unused	 	unused
	[0xeb] = {name='unused', read=read10x},			-- eb 10x	unused	 	unused
	[0xec] = {name='unused', read=read10x},			-- ec 10x	unused	 	unused
	[0xed] = {name='unused', read=read10x},			-- ed 10x	unused	 	unused
	[0xee] = {name='unused', read=read10x},			-- ee 10x	unused	 	unused
	[0xef] = {name='unused', read=read10x},			-- ef 10x	unused	 	unused
	[0xf0] = {name='unused', read=read10x},			-- f0 10x	unused	 	unused
	[0xf1] = {name='unused', read=read10x},			-- f1 10x	unused	 	unused
	[0xf2] = {name='unused', read=read10x},			-- f2 10x	unused	 	unused
	[0xf3] = {name='unused', read=read10x},			-- f3 10x	unused	 	unused
	[0xf4] = {name='unused', read=read10x},			-- f4 10x	unused	 	unused
	[0xf5] = {name='unused', read=read10x},			-- f5 10x	unused	 	unused
	[0xf6] = {name='unused', read=read10x},			-- f6 10x	unused	 	unused
	[0xf7] = {name='unused', read=read10x},			-- f7 10x	unused	 	unused
	[0xf8] = {name='unused', read=read10x},			-- f8 10x	unused	 	unused
	[0xf9] = {name='unused', read=read10x},			-- f9 10x	unused	 	unused
	[0xfa] = {name='invoke-polymorphic', read=read45cc},			-- fa 45cc	invoke-polymorphic {vC, vD, vE, vF, vG}, meth@BBBB, proto@HHHH	A: argument word count (4 bits) B: method reference index (16 bits) C: receiver (4 bits) D..G: argument registers (4 bits each) H: prototype reference index (16 bits)	Invoke the indicated signature polymorphic method. The result (if any) may be stored with an appropriate move-result* variant as the immediately subsequent instruction. The method reference must be to a signature polymorphic method, such as java.lang.invoke.MethodHandle.invoke or java.lang.invoke.MethodHandle.invokeExact. The receiver must be an object supporting the signature polymorphic method being invoked. The prototype reference describes the argument types provided and the expected return type. The invoke-polymorphic bytecode may raise exceptions when it executes. The exceptions are described in the API documentation for the signature polymorphic method being invoked. Present in Dex files from version 038 onwards.
	[0xfb] = {name='invoke-polymorphic/range', read=read4rcc},			-- fb 4rcc	invoke-polymorphic/range {vCCCC .. vNNNN}, meth@BBBB, proto@HHHH	A: argument word count (8 bits) B: method reference index (16 bits) C: receiver (16 bits) H: prototype reference index (16 bits) N = A + C - 1	Invoke the indicated method handle. See the invoke-polymorphic description above for details. Present in Dex files from version 038 onwards.
	[0xfc] = {name='invoke-custom', read=read35c_callsite},			-- fc 35c	invoke-custom {vC, vD, vE, vF, vG}, call_site@BBBB	A: argument word count (4 bits) B: call site reference index (16 bits) C..G: argument registers (4 bits each)	Resolves and invokes the indicated call site. The result from the invocation (if any) may be stored with an appropriate move-result* variant as the immediately subsequent instruction. This instruction executes in two phases: call site resolution and call site invocation. Call site resolution checks whether the indicated call site has an associated java.lang.invoke.CallSite instance. If not, the bootstrap linker method for the indicated call site is invoked using arguments present in the DEX file (see call_site_item). The bootstrap linker method returns a java.lang.invoke.CallSite instance that will then be associated with the indicated call site if no association exists. Another thread may have already made the association first, and if so execution of the instruction continues with the first associated java.lang.invoke.CallSite instance. Call site invocation is made on the java.lang.invoke.MethodHandle target of the resolved java.lang.invoke.CallSite instance. The target is invoked as if executing invoke-polymorphic (described above) using the method handle and arguments to the invoke-custom instruction as the arguments to an exact method handle invocation. Exceptions raised by the bootstrap linker method are wrapped in a java.lang.BootstrapMethodError. A BootstrapMethodError is also raised if: the bootstrap linker method fails to return a java.lang.invoke.CallSite instance. the returned java.lang.invoke.CallSite has a null method handle target. the method handle target is not of the requested type. Present in Dex files from version 038 onwards.
	[0xfd] = {name='invoke-custom/range', read=read3rc_callsite},			-- fd 3rc	invoke-custom/range {vCCCC .. vNNNN}, call_site@BBBB	A: argument word count (8 bits) B: call site reference index (16 bits) C: first argument register (16-bits) N = A + C - 1	Resolve and invoke a call site. See the invoke-custom description above for details. Present in Dex files from version 038 onwards.
	[0xfe] = {name='const-method-handle', read=read21_methodc},			-- fe 21c	const-method-handle vAA, method_handle@BBBB	A: destination register (8 bits) B: method handle index (16 bits)	Move a reference to the method handle specified by the given index into the specified register. Present in Dex files from version 039 onwards.
	[0xff] = {name='const-method-type', read=read21c_proto},			-- ff 21c	const-method-type vAA, proto@BBBB	A: destination register (8 bits) B: method prototype reference (16 bits)	Move a reference to the method prototype specified by the given index into the specified register. Present in Dex files from version 039 onwards.
}

local JavaASMDex = class()
JavaASMDex.__name = 'JavaASMDex'

-- same as JavaASMClass
function JavaASMDex:init(args)
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
function JavaASMDex:fromFile(filename)
	local o = JavaASMDex()
	o:readData((assert(path(filename):read())))
	return o
end


function JavaASMDex:readData(data)
	local blob = ReadBlob(data)

	blob.littleEndian = true	-- by default
	assert.eq(blob:readString(4), 'dex\n')
	local version = blob:readString(4)	-- 3 text chars of numbers with null term ...
--DEBUG:print('version', string.hex(version))
	local checksum = blob:readu4()
--DEBUG:print('checksum = 0x'..bit.tohex(checksum, 8))
	local sha1sig = blob:readString(20)
--DEBUG:print('sha1sig', string.hex(sha1sig))
	local fileSize = blob:readu4()
--DEBUG:print('fileSize', fileSize)
	local headerSize = blob:readu4()
--DEBUG:print('headerSize', headerSize)
	local endianTag = blob:readu4()
--DEBUG:print('endianTag = 0x'..bit.tohex(endianTag, 8))
	if endianTag == 0x78563412 then
		-- then do I flip size and checksum as well?
		blob.littleEndian = false
	elseif endianTag == 0x12345678 then
		-- safe
	else
		io.stderr:write('!!! WARNING !!! endian is a bad value: 0x'..bit.tohex(endianTag, 8)..', something else will probably go wrong.\n')
	end
	assert.eq(fileSize, #data, "fileSize didn't match")	-- when does size not equal #data?

	local numLinks = blob:readu4()
	local linkOfs = blob:readu4()
--DEBUG:print('link count', numLinks,'ofs', linkOfs)
	if numLinks ~= 0 then
io.stderr:write('TODO support dynamically-linked .dex files\n')
	end

	local mapOfs = blob:readu4()
--DEBUG:print('map ofs', mapOfs)

	local numStrings = blob:readu4()
	local stringOfsOfs = blob:readu4()
--DEBUG:print('stringId count', numStrings, 'ofs', stringOfsOfs)

	local numTypes = blob:readu4()
	local typeOfs = blob:readu4()
--DEBUG:print('typeId count', numTypes,'ofs', typeOfs)

	local numProtos = blob:readu4()
	local protoOfs = blob:readu4()
--DEBUG:print('protoId count', numProtos,'ofs', protoOfs)

	local numFields = blob:readu4()
	local fieldOfs = blob:readu4()
--DEBUG:print('fieldId count', numFields,'ofs', fieldOfs)

	local numMethods = blob:readu4()
	local methodOfs = blob:readu4()
--DEBUG:print('methodId count', numMethods,'ofs', methodOfs)

	local numClasses = blob:readu4()
	local classOfs = blob:readu4()
--DEBUG:print('classDef count', numClasses,'ofs', classOfs)

	local numDatas = blob:readu4()
	local dataOfs = blob:readu4()
--DEBUG:print('data count', numDatas,'ofs', dataOfs)


	-- header is done, read structures

	local types = table()
	self.types = types

	-- destroys blobs.ofs
	local function readTypeList(ofs)
		if ofs == 0 then return end
		blob.ofs = ofs
		local numArgs = blob:readu4()
		if numArgs == 0 then return end
		local args = table()
		for i=0,numArgs-1 do
			args[i+1] = assert.index(types, 1+blob:readu2())
		end
		return args
	end


	-- wait is this redundant to the subsequent structures?
	-- or is this the equivalent of the old "constants" table in .class files?
	if mapOfs ~= 0 then
		blob.ofs = mapOfs
		local count = blob:readu4()
		for i=0,count-1 do
			local map = {}
			map.type = assert.index({
				[0] = 'header_item',
				[1] = 'string_id_item',
				[2] = 'type_id_item',
				[3] = 'proto_id_item',
				[4] = 'field_id_item',
				[5] = 'method_id_item',
				[6] = 'class_def_item',
				[7] = 'call_site_id_item',
				[8] = 'method_handle_item',
				[0x1000] = 'map_list',
				[0x1001] = 'type_list',
				[0x1002] = 'annotation_set_ref_list',
				[0x1003] = 'annotation_set_item',
				[0x2000] = 'class_data_item',
				[0x2001] = 'code_item',
				[0x2002] = 'string_data_item',
				[0x2003] = 'debug_info_item',
				[0x2004] = 'annotation_item',
				[0x2005] = 'encoded_array_item',
				[0x2006] = 'annotations_directory_item',
				[0xF000] = 'hiddenapi_class_data_item',
			}, blob:readu2())
			blob:readu2()	-- unused
			map.count = blob:readu4()
			map.offset = blob:readu4()
--DEBUG:print('map['..i..'] = '..require 'ext.tolua'(map))
		end
	end

	-- string offset points to a list of uint32_t's which point to the string data
	-- ... which start with a uleb128 prefix
	assert.le(0, stringOfsOfs)
	assert.le(stringOfsOfs + ffi.sizeof'uint32_t' * numStrings, fileSize)
	local strings = table()
	self.strings = strings
	for i=0,numStrings-1 do
		blob.ofs = stringOfsOfs + ffi.sizeof'uint32_t' * i
		blob.ofs = blob:readu4()
		if blob.ofs < 0 or blob.ofs >= fileSize then
			error("string has bad ofs: 0x"..string.hex(blob.ofs))
		end
		local len = blob:readUleb128()
		local str = blob:readString(len)
		strings[i+1] = str
--DEBUG:print('string['..i..'] = '..str)
	end

	assert.le(0, typeOfs)
	assert.le(typeOfs + ffi.sizeof'uint32_t' * numTypes, fileSize)
	blob.ofs = typeOfs
	for i=0,numTypes-1 do
		types[i+1] = assert.index(strings, blob:readu4()+1)
--DEBUG:print('type['..i..'] = '..types[i+1])
	end

	assert.le(0, protoOfs)
	local sizeofProto = 3*ffi.sizeof'uint32_t'
	assert.le(protoOfs + sizeofProto * numProtos, fileSize)
	local protos = table()
	self.protos = protos
	for i=0,numProtos-1 do
		blob.ofs = protoOfs + i * sizeofProto
		local proto = {}
		-- I don't get ShortyDescritpor ... is it redundant to returnType + args?
		local shorty = assert.index(strings, 1 + blob:readu4())
		local returnType = assert.index(types, 1 + blob:readu4())

		local argsOfs = blob:readu4()
		local argTypes = readTypeList(argsOfs)
		
		-- sig but in .class format:
		local sig = '('..(argTypes and argTypes:concat() or '')..')'..returnType
		protos[i+1] = sig

--DEBUG:print('proto['..i..'] = '..require 'ext.tolua'(protos[i+1]))
	end

	local sizeOfField = 2*ffi.sizeof'uint32_t'
	assert.le(0, fieldOfs)
	assert.le(fieldOfs + sizeOfField * numFields, fileSize)
	blob.ofs = fieldOfs
	self.fields = table()
	for i=0,numFields-1 do
		local field = {}
		self.fields[i+1] = field
		field.class = assert.index(types, 1 + blob:readu2())
		field.sig = assert.index(types, 1 + blob:readu2())
		field.name = assert.index(strings, 1 + blob:readu4())
	end

	assert.le(0, methodOfs)
	assert.le(methodOfs + 2*ffi.sizeof'uint32_t' * numMethods, fileSize)
	blob.ofs = methodOfs
	self.methods = table()
	for i=0,numMethods-1 do
		local method = {}
		self.methods[i+1] = method
		method.class = assert.index(types, 1 + blob:readu2())
		method.sig = deepCopy(assert.index(protos, 1 + blob:readu2()))
		method.name = assert.index(strings, 1 + blob:readu4())
	end

	-- so this is interesting
	-- an ASMDex file can be more than one class
	-- oh well, as long as there's one ASMDex per DexLoader or whatever
	local sizeOfClass = 8 * ffi.sizeof'uint32_t'
	assert.le(0, classOfs)
	assert.le(classOfs + sizeOfClass * numClasses, fileSize)
	self.classes = table()
	for i=0,numClasses-1 do
		blob.ofs = classOfs + i * sizeOfClass
		local class = {}
		self.classes[i+1] = class
		class.thisClass = assert.index(types, 1 + blob:readu4())
		setFlagsToObj(class, blob:readu4(), classAccessFlags)
		class.superClass = assert.index(types, 1 + blob:readu4())
		local interfacesOfs = blob:readu4()
		class.sourceFile = assert.index(strings, 1 + blob:readu4())
		local annotationsOfs = blob:readu4()
		local classDataOfs = blob:readu4()
		local staticValueOfs = blob:readu4()

		-- done reading classdef, read its properties:

		if interfacesOfs ~= 0 then
			class.interfaces = readTypeList(interfacesOfs)
		end

		if annotationsOfs ~= 0 then
			io.stderr:write'TODO annotationsOfs\n'
		end

		if classDataOfs ~= 0 then
			blob.ofs = classDataOfs
--DEBUG:print('reading class data offset from 0x'..bit.tohex(blob.ofs, 8))			
			local numStaticFields = blob:readUleb128()
			local numInstanceFields = blob:readUleb128()
			local numDirectMethods = blob:readUleb128()
			local numVirtualMethods = blob:readUleb128()

			local function readFields(count)
				local fieldIndex = 0
				for i=0,count-1 do
					fieldIndex = fieldIndex + blob:readUleb128()
					local field = assert.index(self.fields, 1 + fieldIndex)
					setFlagsToObj(field, blob:readUleb128(), fieldAccessFlags)
				end
			end
			readFields(numStaticFields)
			readFields(numInstanceFields)

			local function readMethods(count)
				local methodIndex = 0
				for i=0,count-1 do
--DEBUG:local methodStartOfs = blob.ofs					
					methodIndex = methodIndex + blob:readUleb128()
					local method = assert.index(self.methods, 1 + methodIndex)
--DEBUG:print('reading method data', method.class, method.name, method.sig, 'from ofs 0x'..bit.tohex(methodStartOfs, 8))
					setFlagsToObj(method, blob:readUleb128(), methodAccessFlags)
					local codeOfs = blob:readUleb128()
					assert.le(0, codeOfs)
					assert.lt(codeOfs, fileSize)

					if codeOfs ~= 0 then
						local push = blob.ofs	-- save for later since we're in the middle of decoding classDataOfs
--DEBUG:print('method codeOfs', codeOfs)
						blob.ofs = codeOfs

						-- read code
						method.maxReg = blob:readu2()	-- same as "maxLocals" but for registers?
						method.regsIn = blob:readu2()
						method.regsOut = blob:readu2()
						local numTries = blob:readu2()
						local debugInfoOfs = blob:readu4()
						local numInsns = blob:readu4()	-- "in 16-bit code units..." ... this is the number of uint16_t's
--DEBUG:print('method numInsns ', numInsns)
						local instEndOfs = blob.ofs + bit.lshift(numInsns, 1)
						local code = table()
						method.code = code
						while blob.ofs < instEndOfs do
--DEBUG:io.write(bit.tohex(blob.ofs, 8), ':\t')
							-- Is uint16 instruction order influenced by endian order?
							-- "Also, if this happens to be in an endian-swapped file, then the swapping is only done on individual ushort instances and not on the larger internal structures."
							-- ...whatever that means. "Sometimes." smh.
							local op = blob:readu2()
							local lo = bit.band(0xff, op)
							local hi = bit.rshift(op, 8)
							local instDesc = assert.index(instDescForOp, lo)
							local inst = table()
							inst:insert(instDesc.name)
							if not instDesc.read then error("found inst with no read(): "..bit.tohex(lo, 2)) end
							instDesc.read(inst, hi, lo, blob, self)
--DEBUG:print(table.mapi(inst, function(s) return tostring(s) end):concat' ')
							code:insert(inst)
						end
						assert.eq(blob.ofs, instEndOfs, "instruction decoding failed to end at the correct location (current offset vs desired)")

						if bit.band(3, blob.ofs) == 2 then blob:readu2() end	-- optional padding to be 4-byte aligned
						assert.eq(bit.band(3, blob.ofs), 0, "blob ofs supposed to be 4-byte aligned")

--DEBUG:print('method.numTries', numTries)						
						if numTries > 0 then
							assert(not method.tries)
							method.tries = table()
							local lasttry
							for j=0,numTries-1 do
								-- read tries
								local try = {}
								method.tries:insert(try)
								-- "The address is a count of 16-bit code units to the start of the first covered instruction."
								--  so does that mean they are indexes into the insns[] table, or are they byte offsets, or are they file offsets?
								try.startAddr = blob:readu4()
								try.numInsts = blob:readu2()
								try.handlerOfs = blob:readu2()
--DEBUG:print('got try #'..j..':', require 'ext.tolua'(try))
								-- "Elements of the array must be non-overlapping in range and in order from low to high address. "
								if lasttry then
									assert.le(lasttry.startAddr + lasttry.numInsts, try.startAddr, "try begins after previous try ends")
								end
								assert.le(try.startAddr + try.numInsts, numInsns, "try extends past file size")
								lasttry = try
							end
						end

						local encodedCatchHandlerListOfs = blob.ofs

						-- now we're at the end of the code structure
						-- then next is handlers which the tries have offsets into
						-- so now translate tries.handlerOfs into tries.handlers
						if method.tries then
							for tryIndex,try in ipairs(method.tries) do
--DEBUG:print('in method try', tryIndex)
								blob.ofs = encodedCatchHandlerListOfs + try.handlerOfs
								try.handlerOfs = nil
								local catchHandlers = table()
								try.catchHandlers = catchHandlers
								local numCatchHandlers = blob:readUleb128()
--DEBUG:print('numCatchHandlers', numCatchHandlers)
								for j=0,numCatchHandlers-1 do
									local handlers = table()
									catchHandlers:insert(handlers)
									local numCatchTypes = blob:readSleb128()
--DEBUG:print('numCatchTypes', numCatchTypes)
									for k=0,math.abs(numCatchTypes)-1 do
										local addrPair = {}
										local addrType = blob:readUleb128()
										--addrPair.type = assert.index(types, 1 + addrType )	-- I'm getting bad values...
										addrPair.typeIndex = addrType
										addrPair.addr = blob:readUleb128()
--DEBUG:print('addrPair', require 'ext.tolua'(addrPair))
										handlers:insert(addrPair)
									end
									if numCatchTypes < 0 then
										handlers.catchAllAddr = blob:readUleb128()
--DEBUG:print('handlers.catchAllAddr', handlers.catchAllAddr)
									end
								end
							end
						end

						blob.ofs = push
					end
				end
			end
--DEBUG:print('numDirectMethods', numDirectMethods)
--DEBUG:print('numVirtualMethods', numVirtualMethods)
			readMethods(numDirectMethods)
			readMethods(numVirtualMethods)
		end

		if staticValueOfs ~= 0 then
			io.stderr:write'TODO staticValueOfs\n'
		end

--DEBUG:print('class['..i..'] = '..require 'ext.tolua'(class))
	end

--[[
	for i,field in ipairs(self.fields) do
		print('field['..(i-1)..'] = '..require 'ext.tolua'(field))
	end
	for i,method in ipairs(self.methods) do
		print('method['..(i-1)..'] = '..require 'ext.tolua'(method))
	end
--]]

	-- these are now baked into instructions, no longer needed
	self.protos = nil
	self.strings = nil
	self.types = nil
end

-------------------------------- WRITING --------------------------------


return JavaASMDex
