-- this is shorthand for invoking javac to build a .java to a .class
-- it uses make-targets for timestamp checking
-- but for this reason, you have to pass in the src and dst, since it's Java, and you can't tell where the file will end up without parsing it
local os = require 'ext.os'
local Targets = require 'make.targets'

local M = {}

local javaHome = os.getenv'JAVA_HOME'
if not javaHome then
	-- how to know which jvm to load?
	-- this needs to be done only once per app, where to do it?
	local javaLinkPath = io.readproc'which java'
	-- TODO what if it's not a symlink ... ?
	local javaBinaryPath = io.readproc('readlink -f '..javaLinkPath)
--DEBUG:print('javaBinaryPath', javaBinaryPath)
	local path = require 'ext.path'
	local javabindir = path(javaBinaryPath):getdir()	-- java ... /bin/
	javaHome = javabindir:getdir().path				-- java ...
end
M.javaHome = javaHome

-- args: src, dst
function M.C(args)
	require 'make.targets'():add{
		dsts = {args.dst},
		srcs = {args.src},
		rule = function(r)
			assert(os.exec(
				'gcc -I"'
					..javaHome..'/include" -I"'
					..javaHome..'/include/linux" -shared -fPIC -o '
					..args.dst..' '
					..args.src
				)
			)
		end,
	}:runAll()

end

-- args: src, dst
function M.java(args)
	Targets():add{
		dsts = {args.dst},
		srcs = {args.src},
		rule = function(r)
			assert(os.exec('javac '..args.src))
		end,
	}:runAll()
end

return M 
