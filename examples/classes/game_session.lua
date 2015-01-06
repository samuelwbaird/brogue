-- a custom request chain handler that demonstrates adding
-- session information to requests
-- copyright 2014 Samuel Baird MIT Licence

local class = require('core.class')
local rascal = require('rascal.core')
local random_key = require('rascal.util.random_key')

return class(function (game_session)
	local super = game_session.new
	
	function game_session.new()
		local self = super()
		self.session_server = rascal.registry:connect('rascal.session.api')
		return self
	end
	
	function game_session:handle(request, context, response)
		-- is there a cookie with a valid session
		local cookie_header = request.headers.Cookie or ''
		
		-- read the session= value
		local session = cookie_header:match('session=([^;]*);?')
		
		-- if we have a session id, check if its valid
		local session_data = nil
		if session then
			session_data = self.session_server:validate(session)
		end
		
		-- if we have no session data then create a session
		if (not session_data) or (not session_data.name) then
			session_data = {
				name = random_key.printable(4)
			}
			-- save the new session
			local session_id = self.session_server:create(60 * 60 * 24, session_data)
			
			-- set the new cookie
			response:set_header('Set-Cookie', 'session=' .. session_id .. '; Path=/;')
		end
		
		-- add the session data to the context
		context.session_data = session_data
		
		-- invoke the rest of the chain
		return true
	end
end)