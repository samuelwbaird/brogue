-- an open logging server, debug apps and web apps to an open relay log viewer
-- copyright 2022 Samuel Baird MIT Licence

-- configuration settings here
local log_to_console = true
local endpoint_prefix = 'inproc://'
local log_retain_seconds = 60 * 60

local http_worker_threads = 2
local static_cache_seconds = 0

-- reference the brogue libraries
package.path = '../../source/?.lua;' .. package.path

-- use rascal
local rascal = require('rascal.core')

-- configure logging, this service is intended to use in memory storage only, so don't log to disk
rascal.log_service:log_to_console(log_to_console)

-- run the actual server that injests and serves logs
rascal.service('classes.slash_service', { log_retain_seconds, endpoint_prefix })

-- configure an HTTP server, with multiple workers, an API handler and static files
rascal.http_server('tcp://*:8080', http_worker_threads, [[
	prefix('/', {
		-- serve everything from here
		handler('classes.slash_http_handler', { 'static/', ]] .. static_cache_seconds .. [[, 'http://localhost:8080' }),
		
		-- otherwise use server static files, defaulting to index.html
		static('static/', 'index.html', false),
	})
]])

-- last thing to do is run the main event loop
rascal.run_loop()

