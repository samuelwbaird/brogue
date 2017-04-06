-- base global environment code to bootstrap a rascal thread
-- defines detach, as a standard way to split off other threads
-- copyright 2014 Samuel Baird MIT Licence

-- lua modules
local table = require('table')

-- core module, class, array, queue
local array = require('core.array')

-- rascal lua globals --
debug = false
display_worker_code = false

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
elseif not is_detached then
	-- determine if this is the main thread context and has been automatically
	-- created as new versions of lzmq seem to do
	is_main_thread = true
end

-- dummy
log = function (type, text) error('early log ' .. (type or  '')  .. ' ' .. (text or ''), 2) end

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
	thread_code:push('is_detached = true -- global flag that this is a child thread')

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

detach_process = function (code, args)
	-- gather environment arg, encode as hex msgpack binary
	local environment = {}
	environment.shared_globals = shared_globals or {}
	
	-- add argument unpacking to the supplied code and include that code in the environment for safe packing
	local task_code = array()
	task_code:push('local args = ...')
	for name, _ in pairs(args) do
		task_code:push('local ' .. name .. ' = args.' .. name)
	end
	task_code:push(code)
	environment.code = task_code:concat('\n')
	environment.args = args or {}
	
	-- msgpack to encode the environment and hex packing to safely escape it as part of a commandline argument
	local cmsgpack = require('cmsgpack')
	local binary_to_hex = function (binary) return (binary:gsub('.', function (c) return string.format('%02X', string.byte(c)) end)) end
	
	-- preamble
	local process_code = array()
	process_code:push([[local hex_to_binary = function (hex) return (hex:gsub('..', function (cc) return string.char(tonumber(cc, 16)) end)) end]])
	process_code:push([[package.path = hex_to_binary(']] .. binary_to_hex(package.path) .. [[')]])
	process_code:push([[rascal = require('rascal.core')]])

	-- smuggle serialised environment
	process_code:push([[local packed_environment = ']] .. binary_to_hex(cmsgpack.pack(environment)) .. [[']])
	process_code:push([[local environment = cmsgpack.unpack(hex_to_binary(packed_environment))]])
	process_code:push('for key, value in pairs(environment.shared_globals) do')
	process_code:push('	_G[key] = value')
	process_code:push('end')
	process_code:push('is_detached_process = true')

	-- now unpack the smuggled source code and args to begin
	process_code:push('loadstring(environment.code)(environment.args)')

	-- run this packed code as a separate process
	if type(rawget(_G, 'jit')) == 'table' then
		os.execute('luajit -e "' .. process_code:concat(' ') .. '"&')
	else
		os.execute('lua -e "' .. process_code:concat(' ') .. '"&')
	end
end


-- no uninitialised reads or writes to global variables after this
setmetatable(_G, {
	__index = function (obj, property)
		error('uninitialised read from global ' .. tostring(property), 2)
	end,
})

-- optionally prevent uninitialised writes as well
function strict()
	setmetatable(_G, {
		__index = function (obj, property)
			error('uninitialised read from global ' .. tostring(property), 2)
		end,
		__newindex = function (obj, property, value)
			error('uninitialised write to global ' .. tostring(property), 2)
		end,
	})	
end