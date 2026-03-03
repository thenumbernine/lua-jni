--[[
https://source.android.com/docs/core/runtime/dex-format
--]]
local ffi = require 'ffi'
local class = require 'ext.class'
local assert = require 'ext.assert'
local table = require 'ext.table'
local string = require 'ext.string'
local ReadBlob = require 'java.blob'.ReadBlob
local WriteBlob = require 'java.blob'.WriteBlob
local deepCopy = require 'java.util'.deepCopy

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
print('version', string.hex(version))
	local checksum = blob:readu4()
print('checksum = 0x'..bit.tohex(checksum, 8))
	local sha1sig = blob:readString(20)
print('sha1sig', string.hex(sha1sig))
	local fileSize = blob:readu4()
print('fileSize', fileSize)
	local headerSize = blob:readu4()
print('headerSize', headerSize)
	local endianTag = blob:readu4()
print('endianTag = 0x'..bit.tohex(endianTag, 8))
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
print('link count', numLinks,'ofs', linkOfs)
	if numLinks ~= 0 then
io.stderr:write('TODO support dynamically-linked .dex files\n')
	end

	local mapOfs = blob:readu4()
print('map ofs', mapOfs)

	local numStrings = blob:readu4()
	local stringOfsOfs = blob:readu4()
print('stringId count', numStrings, 'ofs', stringOfsOfs)

	local numTypes = blob:readu4()
	local typeOfs = blob:readu4()
print('typeId count', numTypes,'ofs', typeOfs)

	local numProtos = blob:readu4()
	local protoOfs = blob:readu4()
print('protoId count', numProtos,'ofs', protoOfs)

	local numFields = blob:readu4()
	local fieldOfs = blob:readu4()
print('fieldId count', numFields,'ofs', fieldOfs)

	local numMethods = blob:readu4()
	local methodOfs = blob:readu4()
print('methodId count', numMethods,'ofs', methodOfs)

	local numClasses = blob:readu4()
	local classOfs = blob:readu4()
print('classDef count', numClasses,'ofs', classOfs)

	local numDatas = blob:readu4()
	local dataOfs = blob:readu4()
print('data count', numDatas,'ofs', dataOfs)


	-- header is done, read structures

	local types = table()
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
print('map['..i..'] = '..require 'ext.tolua'(map))		
		end
	end

	-- string offset points to a list of uint32_t's which point to the string data
	-- ... which start with a uleb128 prefix
	assert.le(0, stringOfsOfs)
	assert.le(stringOfsOfs + ffi.sizeof'uint32_t' * numStrings, fileSize)
	local strings = table()
	for i=0,numStrings-1 do
		blob.ofs = stringOfsOfs + ffi.sizeof'uint32_t' * i
		blob.ofs = blob:readu4()
		if blob.ofs < 0 or blob.ofs >= fileSize then
			error("string has bad ofs: 0x"..string.hex(blob.ofs)) 
		end
		local len = blob:readUleb128()
		local str = blob:readString(len)
		strings[i+1] = str
		print('string['..i..'] = '..str)
	end

	assert.le(0, typeOfs)
	assert.le(typeOfs + ffi.sizeof'uint32_t' * numTypes, fileSize)
	blob.ofs = typeOfs
	for i=0,numTypes-1 do
		types[i+1] = assert.index(strings, blob:readu4()+1)
print('type['..i..'] = '..types[i+1])
	end

	assert.le(0, protoOfs)
	local sizeofProto = 3*ffi.sizeof'uint32_t'
	assert.le(protoOfs + sizeofProto * numProtos, fileSize)
	local protos = table()
	for i=0,numProtos-1 do
		blob.ofs = protoOfs + i * sizeofProto 
		local proto = {}
		-- I don't get ShortyDescritpor ... is it redundant to returnType + args?
		proto.shorty = assert.index(strings, 1 + blob:readu4())
		-- TODO I'm probably going to have to JNISig-to-sig or something here
		-- TODO how come when the shorty says return-type-void, I get return type as an excption here?
		-- TODO what's an empty return type string mean?
		proto.returnType = assert.index(strings, 1 + blob:readu4())
		
		local argsOfs = blob:readu4()
		proto.args = readTypeList(argsOfs)
		protos[i+1] = proto
print('proto['..i..'] = '..require 'ext.tolua'(protos[i+1]))
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
		method.proto = deepCopy(assert.index(protos, 1 + blob:readu2()))
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
		class.accessFlags = blob:readu4()
		class.superClass = assert.index(types, 1 + blob:readu4())
		local interfacesOfs = blob:readu4()
		class.sourceFile = assert.index(strings, 1 + blob:readu4())
		local annotationsOfs = blob:readu4()
		local classDataOfs = blob:readu4()
		local staticValuesOfs = blob:readu4()

		-- done reading classdef, read its properties:

		if interfacesOfs ~= 0 then
			class.interfaces = readTypeList(interfacesOfs)
		end

		if annotationsOfs ~= 0 then
			io.stderr:write'TODO annotationsOfs\n'
		end

		if classDataOfs ~= 0 then
			blob.ofs = classDataOfs 
			local numStaticFields = blob:readUleb128()
			local numInstanceFields = blob:readUleb128()
			local numDirectMethods = blob:readUleb128()
			local numVirtualMethods = blob:readUleb128()
			
			local function readFields(count)
				local fieldIndex = 0
				for i=0,count-1 do
					fieldIndex = fieldIndex + blob:readUleb128()
					assert.index(self.fields, 1 + fieldIndex).accessFlags = blob:readUleb128()
				end
			end
			readFields(numStaticFields)
			readFields(numInstanceFields)

			local function readMethods(count)
				local methodIndex = 0
				for i=0,count-1 do
					methodIndex = methodIndex + blob:readUleb128()
					local method = assert.index(self.methods, 1 + methodIndex)
					method.accessFlags = blob:readUleb128()
					local codeOfs = blob:readUleb128()
					assert.le(0, codeOfs)
					assert.lt(codeOfs, fileSize)
-- [[
					if codeOfs ~= 0 then
						local push = blob.ofs	-- save for later since we're in the middle of decoding classDataOfs
--DEBUG:print('method codeOfs', codeOfs)					
						blob.ofs = codeOfs
							
						-- read code
						method.numRegs = blob:readu2()
						method.numIn = blob:readu2()
						method.numOut = blob:readu2()
						local numTries = blob:readu2()
						local debugInfoOfs = blob:readu4()
						local numInsns = blob:readu4()	-- "in 16-bit code units..."
--DEBUG:print('method numInsns ', numInsns)
						local insns = blob:readString(numInsns * 2)
						if bit.band(3, blob.ofs) == 2 then blob:readu2() end	-- optional padding to be 4-byte aligned
						if numTries > 0 then
							method.tries = table()
							for j=0,numTries-1 do
								-- read tries
								local try = {}
								method.tries:insert(try)
								try.startAddr = blob:readu4()
								try.insnCount = blob:readu2()
								try.handlerOfs = blob:readu2()
--DEBUG:print('got method try', require 'ext.tolua'(try))							
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
--]]				
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

	for i,field in ipairs(self.fields) do
		print('field['..(i-1)..'] = '..require 'ext.tolua'(field))
	end
	for i,method in ipairs(self.methods) do
		print('method['..(i-1)..'] = '..require 'ext.tolua'(method))
	end
end

return JavaASMDex
