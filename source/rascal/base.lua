-- base global environment code to bootstrap a rascal thread
-- defines detach, as a standard way to split off other threads
-- copyright 2014 Samuel Baird MIT Licence

-- lua modules
local table = require('table')

-- core module, class, array, queue
local array = require('core.array')

-- rascal lua globals --
debug = false
display_worker_code = debug and false

-- zeromq modules
zmq = require('lzmq')
zloop = require('lzmq.loop')
zthreads = require('lzmq.threads')

-- am I the main thread
is_main_thread = false
ctx = zthreads.get_parent_ctx()

if not ctx then
	is_main_thread = true
	ctx = zmq.init(1)
end

-- dummy
log = function () end

-- loop for this thread
loop = zloop.new()

-- share simple global values with other threads
local shared_globals = {}
share_global = function (key, value)
	_G[key] = value
	shared_globals[key] = value
end
share_globals = function (table)
	for key, value in pairs(table) do
		share_global(key, value)
	end
end

-- TODO: include function to include inline code as a called function?

-- run a service in its own thread
detach = function (code, args)
	local thread_code = array()

	args = args or {}
	args.package_path = package.path
	args.shared_globals = shared_globals

	-- preamble
	thread_code:push([[local args = ...]])
	for name, _ in pairs(args) do
		thread_code:push('local ' .. name .. ' = args.' .. name)
	end
	thread_code:push('package.path = package_path')
	thread_code:push('for key, value in pairs(shared_globals) do')
	thread_code:push('	_G[key] = value')
	thread_code:push('end')

	-- insert custom code
	if type(code) == 'string' then
		thread_code:push(code)
	elseif type(code) == 'table' then
		for _, line in ipairs(code) do
			thread_code:push(line)
		end
	end

	-- assemble the code
	local code_string = table.concat(thread_code, '\n')

	-- print code and test compile
	if display_worker_code then
		print('-- launch worker')
		print(code_string)
	end
	if debug then
		local fn, error = loadstring(code_string, 'worker')
		assert(fn, error)
	end

	zthreads.run(ctx, code_string, args):start(true)
end