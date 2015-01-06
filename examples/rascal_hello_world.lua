-- simplest rascal HTTP server
-- copyright 2014 Samuel Baird MIT Licence

-- reference the brogue libraries
package.path = '../source/?.lua;' .. package.path

-- demonstrate the basic template for a rascal based server
-- load and configure rascal
-- configure one http server as the path into the server
-- kick off the main loop

-- use rascal
local rascal = require('rascal.core')

-- configure logging
rascal.log_service:log_to_file('log/rascal_hello_world.log')
rascal.log_service:log_to_console(true)

-- configure an HTTP server
rascal.http_server('tcp://*:8080', 1, [[
	prefix('/', {
		-- serve the static folder and index.html by default, set caching on/off
		static('static/', 'index.html', false),
	})
]])

log('open your browser at http://localhost:8080/')
log('ctrl-c to exit')

-- last thing to do is run the main event loop
rascal.run_loop()

