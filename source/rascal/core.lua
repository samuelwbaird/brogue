-- all rascal services must include the core rascal module
-- for convenient access to logging, the registry and the main loop
-- copyright 2014 Samuel Baird MIT Licence

require('rascal.base')

-- lua modules
local table = require('table')

-- external modules
local cmsgpack = require('cmsgpack')

-- core modules
local array = require('core.array')
local module = require('core.module')

local proxy_client = require('rascal.proxy.client')
local proxy_server = require('rascal.proxy.server')

if is_main_thread then
	require('rascal.bootstrap.main_thread')
end

return module(function (rascal)
	
	-- secondary services ---------------------------------------------------------------------------------
	
	function rascal.service(class_name, class_args)
		detach({
			[[rascal = require('rascal.core')]],
			[[proxy_client = require('rascal.proxy.client')]],
			[[proxy_server = require('rascal.proxy.server')]],
			[[-- require the service and instantiate a standard class with args]],
			[[local service = require(class_name) (unpack(cmsgpack.unpack(class_args)))]],
			[[log('service', class_name)]],
			[[rascal.run_loop()]],
		}, {
			class_name = class_name,
			class_args = cmsgpack.pack(class_args or {})
		})
	end
	
	-- http -------------------------------------------------------------------------------------------------
	
	function rascal.http_server(address, number_of_workers, configuration)
		-- sanity check the configuration
		local worker = require('rascal.http.worker')
		local check_handler = worker.create_handler(configuration)		
		
		-- prepare the threads
		local worker_request_address = 'inproc://http_worker_request'
		local push_reply_address = 'inproc://http_worker_reply'
		
		number_of_workers = number_of_workers or 1
		for i = 1, number_of_workers do
			detach({
				[[local rascal = require('rascal.core')]],
				[[proxy_client = require('rascal.proxy.client')]],
				[[proxy_server = require('rascal.proxy.server')]],
				[[local http_worker = require('rascal.http.worker')]],
				[[local worker = http_worker(configuration, worker_request_address, push_reply_address, worker_id)]],
				[[rascal.run_loop()]],
			}, {
				configuration = configuration,
				worker_request_address = worker_request_address,
				push_reply_address = push_reply_address,
				worker_id = 'worker' .. i
			})
		end
		
		detach({
			[[local rascal = require('rascal.core')]],
			[[local http_server = require('rascal.http.server')]],
			[[http_server.bind(address, worker_request_address, push_reply_address)]],
			[[rascal.run_loop()]],
		}, {
			address = address, 
			worker_request_address = worker_request_address,
			push_reply_address = push_reply_address
		})
	end
	
	function rascal.shell(services)
		detach({
			[[rascal = require('rascal.core')]],
			[[proxy_client = require('rascal.proxy.client')]],
			[[proxy_server = require('rascal.proxy.server')]],
			[[log('shell', table.concat(services, ' '))]],
			[[local shell = require('rascal.session.shell') (services)]],
			[[loop:sleep_ex(500)]],
			[[shell:loop()]],
		}, {
			services = services,
		})
	end
		
	-- core services ---------------------------------------------------------------------------------------
	
	-- log -------------------------------------------------------------------------------------------------
	
	rascal.log_service = require('rascal.log').client()
	-- allow direct access to main log output command
	rascal.log = function (...)
		rascal.log_service:log(...)
	end
	-- and as a global
	log = rascal.log
	
	-- registry --------------------------------------------------------------------------------------------
	
	rascal.registry = require('rascal.registry').client()

	-- main loop --------------------------------------------------------------------------------------------
	
	-- run the main loop for this thread
	function rascal.run_loop(tick_time, tick_function)
		local complete, error = pcall(function ()
			loop:start(tick_time, tick_function)
		end)
		if not complete then
			log('rascal runloop error', error)
		end
		if is_main_thread then
			rascal.log('shutting down')
			loop:poll(100)
			ctx:term()
		end
	end
end)