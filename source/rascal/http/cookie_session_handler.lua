-- a handler that checks and sets a session cookie in the http
-- request, communicates with rascal session_server to store the session
-- copyright 2014 Samuel Baird MIT Licence

local class = require('core.class')
local rascal = require('rascal.core')

return class(function (cookie_session)
	
	function cookie_session:init(timeout_seconds, session_api_endpoint)
		self.timeout_seconds = timeout_seconds or (60 * 60 * 24)
		self.session_server = rascal.registry:connect(session_api_endpoint or 'rascal.session.api')
	end
	
	function cookie_session:handle(request, context, response)
		-- is there a cookie that might have a valid session?
		local cookie_header = request.headers.cookie or ''
		
		-- read the session= value
		local session_id = cookie_header:match('session=([^;]*);?')
		
		-- if we have a session id, check if its valid
		local session_data = session_id and self.session_server:validate(session_id)
		
		if session_data then
			-- if we have session data then pass it through the chain
			context.session_id = session_id
			context.session_data = session_data
			
		else
			-- if we have no session data then create a session
			
			-- save the new session
			local session_data = {}
			local session_id = self.session_server:create(self.timeout_seconds, session_data)
			
			-- set the new cookie
			response:set_header('Set-Cookie', 'session=' .. session_id .. '; Path=/;')
			
			-- signal that the session was just created and pass the data through the chain
			context.session_id = session_id
			context.session_data = session_data
			context.session_created = true
		end
		
		-- invoke the rest of the chain
		return true
	end
end)