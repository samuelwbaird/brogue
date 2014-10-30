-- reference the brogue libraries
package.path = '../source/?.lua;' .. package.path

-- demonstrate a game server with the following features
-- sessions using cookies (no real security)
-- long polling status updates
-- rascal proxies used to run game logic in its own thread

-- use rascal
local rascal = require('rascal.core')

-- configure logging
rascal.log_service:log_to_file('log/game_server.log')
rascal.log_service:log_to_console(true)

-- standard rascal session db
rascal.service('rascal.session.session_server', { 'db/session.sqlite' })

-- we are going to use the game of blockers and runners
-- as demonstrated in the ORM example
-- the game will run in its own microserver process

-- launch this class as a micro server, with these parameters
rascal.service('classes.game_thread', { 'db/game.sqlite' })


-- configure an HTTP server
rascal.http_server('tcp://*:8080', 1, [[
	prefix('/', {
		-- chain in our custom handler
		chain('classes.game_session', {}, {
			prefix('api_', {
				handler('classes.game_api', {}),
			}),
			handler('classes.game_view', {}),
		}),
		redirect('/')
	})
]])

log('open your browser at http://localhost:8080/')
log('ctrl-z to exit')

-- last thing to do is run the main event loop
rascal.run_loop()

