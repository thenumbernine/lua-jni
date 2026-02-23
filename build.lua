local table = require 'ext.table'	-- table
local os = require 'ext.os'	-- os.exec
local io = require 'ext.io'	-- io.readproc

local M = {}

-- This is only used in two places:
-- 1) Here by java.build.java / java.build.C
-- 2) When creating a new JavaVM Lua wrapper object, for the sake of finding the libjvm.so file.
-- and detecting it is problematic
function M.getJavaHome()
	if M.javaHome then return M.javaHome end
	M.javaHome = os.getenv'JAVA_HOME'
	if not M.javaHome then
		-- how to know which jvm to load?
		-- this needs to be done only once per app, where to do it?
		local javaLinkPath = io.readproc'which java'
		-- TODO what if it's not a symlink ... ?
		local javaBinaryPath = io.readproc('readlink -f '..javaLinkPath)
	--DEBUG:print('javaBinaryPath', javaBinaryPath)
		local path = require 'ext.path'
		local javabindir = path(javaBinaryPath):getdir()	-- java ... /bin/
		M.javaHome = javabindir:getdir().path				-- java ...
	end
	return assert(M.javaHome, "failed to find JAVA_HOME or readlink -f `which java`")
end

-- The following are shorthand for invoking javac to build a .java to a .class
-- it uses make-targets for timestamp checking
-- but for this reason, you have to pass in the src and dst, since it's Java, and you can't tell where the file will end up without parsing it

-- args: src, dst
function M.java(args)
	local Targets = require 'make.targets'
	Targets():add{
		dsts = {args.dst},
		srcs = {args.src},
		rule = function(r)
			assert(os.exec('javac '..args.src))
		end,
	}:runAll()
end

-- Same but for building .c to .so with the JAVA_HOME stuff included
-- args: src, dst
function M.C(args)
	local Targets = require 'make.targets'
	Targets():add{
		dsts = {args.dst},
		srcs = {args.src},
		rule = function(r)
			assert(os.exec(table{
				'gcc',
				'-I"'..M.getJavaHome()..'/include"',
				'-I"'..M.getJavaHome()..'/include/linux"',
				'-shared',
				'-fPIC',
				'-o',args.dst,
				args.src
			}:concat' '))
		end,
	}:runAll()

end

return M 
