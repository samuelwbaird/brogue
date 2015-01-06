-- http server with custom chain and resource handlers
-- copyright 2014 Samuel Baird MIT Licence

-- reference the brogue libraries
package.path = '../source/?.lua;' .. package.path

-- demonstrate adding some custom functionality to the basic web server
-- add a custom chain, that chains access to other handlers
-- add a custom handler to actually handles some request
-- serve custom.html by default to demonstrate

-- use rascal
local rascal = require('rascal.core')

-- configure logging
rascal.log_service:log_to_file('log/rascal_custom_world.log')
rascal.log_service:log_to_console(true)

-- configure an HTTP server
rascal.http_server('tcp://*:8080', 1, [[
	prefix('/', {
		-- chain in our custom handler
		chain('classes.rascal_custom_chain', {}, {
			
			-- if the url matches then use our custom handler to supply the response
			equal('time.html', {
				handler('classes.rascal_custom_handler', {})
			}),
			
			-- otherwise use server static files, defaulting to custom.html
			static('static/', 'custom.html', false),
		})
	})
]])

log('open your browser at http://localhost:8080/')
log('ctrl-c to exit')

-- last thing to do is run the main event loop
rascal.run_loop()

