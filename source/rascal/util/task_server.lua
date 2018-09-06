-- manage a pool of worker threads running arbitrary lua tasks
-- copyright 2017 Samuel Baird MIT Licence

local class = require('core.class')
local array = require('core.array')

local rascal = require('rascal.core')

local proxy_client = require('rascal.proxy.client')
local proxy_server = require('rascal.proxy.server')

local random_key = require('rascal.util.random_key')

return class(function (task_server)
	
	local worker_api_description = {
		worker_is_idle = 'worker_id:string',
		worker_did_yield_result = 'worker_id:string, result:*',
		worker_request_work = 'worker_id:string -> task:*',
		worker_did_close = 'worker_id:string',
		
		-- allow a proxy inside tasks to queue more tasks
		worker_queue_lua = 'lua_source:string, parameters:*',
		worker_queue_lua_file = 'lua_filename:string, parameters:*',
	}

	local publish_signal_api_description = {
		worker_signal_waiting = '',
		worker_signal_close = '',
	}
	
	function task_server:init(no_workers, use_external_process)
		self.id = 'task_server:' .. random_key.printable(16)
		if use_external_process then
			self.channel_prefix = 'ipc://' .. self.id
		else
			self.channel_prefix = 'inproc://' .. self.id
		end
		
		-- push and pop work queue as a stack, pop newest task, not oldest task, to limit overfilling queues from several layers of producers
		self.workers = {}
		self.work_queue = array()
		
		proxy_server(self, worker_api_description, self.channel_prefix .. '.api', zmq.REP)
		self.publish = proxy_server(self, publish_signal_api_description, self.channel_prefix .. '.pub', zmq.PUB)
		
		for i = 1, no_workers do
			self:add_worker(i, use_external_process)
		end
	end
	
	function task_server:add_worker(worker_id, use_external_process)
		local worker = {
			id = worker_id,
			idle = true,
			on_result = nil
		}
		self.workers[worker_id] = worker

		-- implement external process version of detach
		if use_external_process then
			detach_process("require('rascal.util.task_server').run_as_worker(worker_id, channel_prefix)", { worker_id = worker_id, channel_prefix = self.channel_prefix })
		else
			detach("require('rascal.util.task_server').run_as_worker(worker_id, channel_prefix)", { worker_id = worker_id, channel_prefix = self.channel_prefix })
		end
	end
	
	-- usage API --
	
	function task_server:queue_lua(lua_source, parameters, on_result, task_or_filename)
		self.work_queue:push({
			lua_source = lua_source,
			parameters = parameters,
			on_result = on_result,
			name = task_or_filename or '<anonymous_task>',
		})
		
		self.publish:worker_signal_waiting()
	end
	
	function task_server:queue_lua_file(lua_filename, parameters, on_result)
		local input = assert(io.open(lua_filename, 'r'), 'could not read lua task file ' .. lua_filename)
		local source = input:read('*a')
		input:close()
		
		return self:queue_lua(source, parameters, on_result, lua_filename)
	end
	
	function task_server:is_complete()
		if not self.work_queue:is_empty() then
			return false
		end	
		
		for _, worker in pairs(self.workers) do
			if not worker.idle then
				return false
			end
		end
		
		return true
	end
	
	function task_server:close()
		while true do
			self.publish:worker_signal_close()
			loop:sleep_ex(100)
			local all_closed = true
			for _, worker in pairs(self.workers) do
				if not worker.closed then
					all_closed = false
				end
			end
			if all_closed then
				break
			end
		end
	end
	
	function task_server:complete(close)
		-- keep polling the main event loop until the task server is marked as complete
		while not self:is_complete() do
			loop:sleep_ex(100)
		end
		
		if close then
			self:close()
		end

		-- clean up events
		loop:sleep_ex(100)
	end
	
	-- worker API --
	
	function task_server:worker_is_idle(worker_id)
		local worker = self.workers[worker_id]
		if worker then
			worker.on_result = nil
			worker.idle = true
		end
	end
	
	function task_server:worker_did_yield_result(worker_id, result)
		local worker = self.workers[worker_id]
		if worker and worker.on_result then
			worker.on_result(result)
		end
	end
	
	function task_server:worker_request_work(worker_id)
		local worker = self.workers[worker_id]
		local task = self.work_queue:pop()
		if worker and task then
			worker.idle = false
			worker.on_result = task.on_result
			return {
				name = task.name,
				lua_source = task.lua_source,
				parameters = task.parameters,
			}
		end
	end
	
	function task_server:worker_did_close(worker_id)
		local worker = self.workers[worker_id]
		if worker then
			worker.closed = true
		end
	end

	function task_server:worker_queue_lua(...)
		return self:queue_lua(...)
	end
	
	function task_server:worker_queue_lua_file(...)
		return self:queue_lua_file(...)
	end
	
	function task_server.run_as_worker(worker_id, channel_prefix)
		local working = false
		local api = proxy_client(channel_prefix .. '.api', zmq.REQ, worker_api_description)
		
		local function handle_work(name, lua_source, parameters)
			local thread_code = array()

			-- create the environment of local vars for this function
			local environment = {}
			environment.worker_id = worker_id
			environment.api = api
			if parameters then
				for k, v in pairs(parameters) do
					environment[k] = v
				end
			end

			-- preamble
			thread_code:push([[local environment = ...]])
			for name, _ in pairs(environment) do
				thread_code:push('local ' .. name .. ' = environment.' .. name)
			end
			-- insert some direct proxy functions
			thread_code:push('yield = function (value) api:worker_did_yield_result(worker_id, value) end')
			thread_code:push('queue_lua = function (source, parameters, on_result) assert(on_result == nil, "no callback possible on worker queued task") api:worker_queue_lua(source, parameters) end')
			thread_code:push('queue_lua_file = function (filename, parameters, on_result) assert(on_result == nil, "no callback possible on worker queued task") api:worker_queue_lua_file(lua_filename, parameters) end')

			-- assemble the code
			thread_code:push(lua_source)
			local code_string = table.concat(thread_code, ' ')

			-- print(code_string)
			
			-- compile task code
			local fn, message = loadstring(code_string, name)
			if not fn then
				error(message .. '\n' .. code_string)
			end
			
			-- finally run the task
			fn(environment)
		end
		
		local function request_work_if_idle()
			if working then
				return
			end
			
			working = true
			local task = api:worker_request_work(worker_id)
			if not task then
				working = false
				return
			end
			
			local success, result = pcall_trace(handle_work, task.name, task.lua_source, task.parameters)
			if success then
				if type(result) ~= 'nil' then
					api:worker_did_yield_result(worker_id, result)
				end
			else
				log('error in task: [' .. task.name ..'] ' .. result)
			end

			working = false
			api:worker_is_idle(worker_id)			

			-- check again for work after full callstack unwind
			loop:add_time(1, request_work_if_idle)
		end

		-- connect signals from the co-ordinator push API
		local signals = {
			worker_signal_waiting = request_work_if_idle,
			worker_signal_close = function ()
				api:worker_did_close(worker_id)
				loop:sleep_ex(1000)
				loop:stop()
			end
		}
		proxy_server(signals, publish_signal_api_description, channel_prefix .. '.pub', zmq.SUB)
		
		-- connect timer event as a fall back from published signals
		loop:add_interval(500, request_work_if_idle)
		
		-- once the loop starts request the first work
		loop:add_time(0, request_work_if_idle)
		
		-- event loop driven from now on
		rascal.run_loop()
	end
	
end)

