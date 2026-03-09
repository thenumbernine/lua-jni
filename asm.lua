-- I have enough common stuff between ASMDex and ASMClass that I'll just put it here...
local class = require 'ext.class'
local table = require 'ext.table'
local assert = require 'ext.assert'
local string = require 'ext.string'
local path = require 'ext.path'

local java_util = require 'java.util'
local getDotSepName = java_util.getDotSepName
local sigStrToObj = java_util.sigStrToObj


local JavaASM = class()

-- ; is a popular asm comment syntax, right?
-- yeah but it's also a part of java method syntax
-- meaning either space should be part of the comment as well, i.e. ';%s',
-- or we should use another character...
JavaASM.lineComment = '#'

function JavaASM:init(args)
	if type(args) == 'string' then
		self:readData(args)	-- assume its raw data
	elseif type(args) == 'nil' then
		-- empty class
	elseif type(args) == 'table' then
		self:fromArgs(args)
	else
		error("idk how to init this")
	end
end

-- static ctor
function JavaASM:fromFile(filename)

	-- assert this is a class and not an object ...
	-- i.e. assert its metatable is the ext.class's class-metatable
	assert(not JavaASM:isa(getmetatable(self)))

	local o = self()
	o:readData((assert(path(filename):read())))
	return o
end

-- called from :init() to build a JavaASM from arguments for :compile()'ing later:
function JavaASM:fromArgs(args)
	for k,v in pairs(args) do
		self[k] = v
	end

	-- while we're here, prepare / validate args:
	for _,method in ipairs(self.methods) do
		-- parse method.code if it is instructions
		-- TODO better string quote parsing, and better type detection
		if type(method.code) == 'string' then

			-- argument validation:
			-- do this here or upon ctor?
			method.code = string.split(string.trim(method.code), '\n')
				:mapi(function(line)
					local i = line:find(self.lineComment,1,true)
					if i then
						line = line:sub(1,i-1)
					end
					return string.trim(line)
				end)
				:mapi(function(line)
					return string.split(line, '%s+')
				end)
		end
	end
end

-- shorthand for env:_defineClass(self, ...)
function JavaASM:_defineClass(env, ...)
	return env:_defineClass(self, ...)
end


local function tokenToValue(value)
-- TODO use this for data in instructions
-- TODO .value writing should be compatible between .class and .dex
	-- convert value into a constant entry here
	if value == 'true' then
		-- wait how are bool constants stored?
		return {tag='int', value=1}
	end
	if value == 'false' then
		return {tag='int', value=0}
	end
	if value:match'L$' then
		local rest = value:match'^(.*)L$'
		assert(tonumber(rest))
		-- as a string?
		-- TODO how to parse int64_t here...
		return {tag='long', value=rest}
	end

	local num = tonumber(value)
	if num then
		if value:find'%.' then
			return {tag='float', value=value}
		else
			return {tag='int', value=value}
		end
	end

	-- not a constant, assume strings already handled
	-- so fail
	return nil
end

-- split line into tokens
local function tokenizeLine(line)
	--[[ lazy way
	return string.split(line, '%s+')
	--]]
	-- [[ better?
	local parts = table()
	while line ~= '' do
		if line:match'^"' then
			-- TODO read and skip escaped quotes ...
			local searchStart = 1
			while true do
				local closeIndex = line:find('"', searchStart, true)
				if line:sub(closeIndex-1,closeIndex-1) == '\\' then
					-- escaped, keep going
					searchStart = closeIndex+1
				else
					assert(line:sub(closeIndex+1, closeIndex+1) == ''
						or line:sub(closeIndex+1, closeIndex+1):match'%s',
						"got an ill-formatted string with trailing characters")
					-- not escaped, close
					local value = require 'ext.fromlua'(
						line:sub(1, closeIndex)
					)

					parts:insert{tag='string', value=value}

					line = string.trim(line:sub(closeIndex+1))
					break
				end
			end
		else
			-- not a string, assume its a literal
			-- TODO in here, parse out numbers
			local first, rest = line:match'^(%S+)%s+(.*)$'
			if not first then
				line = tokenToValue(line) or line
				-- then we're at the last token
				parts:insert(line)
				break
			end
			if first then
				first = tokenToValue(first) or first
				parts:insert(first)
				line = rest
			end
		end
	end
	return parts
	--]]
end

-- ok here's my attempt at an asm code for java
-- I'll model it somewhat like jasmin: https://jasmin.sourceforge.net/guide.html
-- but no promises, esp how their method refs are a single amalgamation of java/lang/class/path/methodName(Ljni/sig/methods;)V ... nah I'll pass on that.
function JavaASM:fromAsm(code)

	-- assert this is a class and not an object ...
	-- i.e. assert its metatable is the ext.class's class-metatable
	assert(not JavaASM:isa(getmetatable(self)))

	local currentMethod
	local args = {}
	local lines = string.split(code, '\n')
	for _,line in ipairs(lines) do
		line = line:match('^(.-)'..string.patescape(self.lineComment)) or line
		line = string.trim(line)
		if line == '' then goto lineDone end
		local sourceFileDef = line:match'^%.source%s+(.-)$'	-- .source
		if sourceFileDef then
			args.sourceFile = sourceFileDef
			goto lineDone
		end
		local function applyClassFlags(parts)
			for _,part in ipairs(parts) do
				args[assert.index({
					public = 'isPublic',
					final = 'isFinal',
					super = 'isSuper',	-- when is this used?
					interface = 'isInterface',
					abstract = 'isAbstract',
				}, part, 'unknown class access-flag')] = true
			end
		end
		do
			local classDef = line:match'^%.class%s+(.-)$'	-- .class
			if classDef then
				local parts = string.split(classDef, '%s+')
				args.thisClass = parts:remove()	-- last is class name, rest are access flags
				applyClassFlags(parts)
				goto lineDone
			end
		end
		do
			local interfaceDef = line:match'^%.interface%s+(.-)$'	-- .interface
			if interfaceDef then
				local parts = string.split(interfaceDef, '%s+')
				assert(not args.thisClass, "can't use .interface and .class at the same time")
				args.thisClass = parts:remove()
				args.isInterface = true
				applyClassFlags(parts)
				goto lineDone
			end
		end
		local superClassDef = line:match'^%.super%s+(.-)$'	-- .super
		if superClassDef then
			args.superClass = superClassDef
			goto lineDone
		end
		local implementsClass = line:match'^%.implements%s+(.-)$'	-- .implements
		if implementsClass then
			args.interfaces = args.interfaces or table()
			args.interfaces:insert(implementsClass)
			goto lineDone
		end
		do
			local fieldDef = line:match'^%.field%s+(.-)$'	--- .field
			if fieldDef then
				local field = {}

-- TODO use line tokenizer below that notices quotes
				local parts = string.split(fieldDef, '%s+')

				if parts[#parts-1] == '=' then
					local value = parts:remove()
					parts:remove()
					field.value = value
				end
				field.sig = assert(parts:remove(), "expected field signature")
				field.sig = getDotSepName(field.sig)
				field.name = assert(parts:remove(), "expected field name")
				for _,part in ipairs(parts) do
					field[assert.index({
						public = 'isPublic',
						private = 'isPrivate',
						protected = 'isProtected',
						static = 'isStatic',
						final = 'isFinal',
						volatile = 'isVolatile',
						transient = 'isTransient',
					}, part, 'unknown field access-flag')] = true
				end
				args.fields = args.fields or table()
				args.fields:insert(field)
				goto lineDone
			end
		end
		do
			-- TODO hand this off to another method, from lines .method to .end method,
			-- and allow methods[] to contain strings to be parsed by this?
			local methodDef = line:match'^%.method%s+(.-)$'	--- .method
			if methodDef then
				local method = {}
				local parts = string.split(methodDef, '%s+')
				method.sig = assert(parts:remove(), "expected sig")
				method.sig = sigStrToObj(method.sig)
				method.name = assert(parts:remove(), "expected name")
				for _,part in ipairs(parts) do
					method[assert.index({
						public = 'isPublic',
						private = 'isPrivate',
						protected = 'isProtected',
						static = 'isStatic',
						final = 'isFinal',
						synchronized = 'isSynchronized',
						native = 'isNative',
						abstract = 'isAbstract',
						constructor = 'isConstructor',
					}, part, 'unknown method access-flag')] = true
				end
				args.methods = args.methods or table()
				args.methods:insert(method)
				currentMethod = method
				goto lineDone
			end
		end
		if line:match'^%.end%s+method$' then
			currentMethod = nil
			goto lineDone
		end
		if currentMethod then
			-- jasmin syntax:
			local maxStackDef = line:match'^%.limit%s+stack%s+(.*)$'
			if maxStackDef then
				currentMethod.maxStack = assert(tonumber(maxStackDef))
				goto lineDone
			end
			local maxLocalsDef = line:match'^%.limit%s+stack%s+(.*)$'
			if maxLocalsDef then
				currentMethod.maxLocals = assert(tonumber(maxLocalsDef))
				goto lineDone
			end
			-- sort of smali syntax:
			-- .registers <maxRegs> [<regsIn>] [<regsOut>]
			local maxRegsDef = line:match'^%.registers%s+(.*)$'
			if maxRegsDef then
				local values = string.split(maxRegsDef, '%s+')
				currentMethod.maxRegs = assert(tonumber(values[1]))
				currentMethod.regsIn = tonumber(values[2])
				currentMethod.regsOut = tonumber(values[3])
				goto lineDone
			end
			-- TODO .line
			-- TODO .var
			-- TODO .throws
			-- TODO .catch
			-- parse instructions as line contents
			-- TODO types, like field values
			-- for now I require type indicators preceding the instruction

			local parts = tokenizeLine(line)

			assert.index(self.opForInstName, parts[1], "got an unknown instruction")
			currentMethod.code = currentMethod.code or table()
			currentMethod.code:insert(parts)
			goto lineDone
		end
		error("got a line I couldn't understand: "..line)
::lineDone::
	end

	return self(args)
end

return JavaASM
