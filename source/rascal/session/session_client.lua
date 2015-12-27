-- minimises the overhead of working with a shared session server
-- across multiple processes by caching recently used data
-- and recieving updates from the cache server via pub/sub
-- copyright 2014 Samuel Baird MIT Licence

-- standard lua
local io = require('io')
local string = require('string')

-- core modules
local class = require('core.class')
local array = require('core.array')
local cache = require('core.cache')

local rascal = require('rascal.core')

return class(function (session_client)

	function session_client:init()
		-- cache session info in each worker to reduce contention
		self.cache = cache(1024 * 64)
		-- connect to the real session server as required
		self.session_api = rascal.registry:connect('rascal.session.api')
		self.session_push = rascal.registry:connect('rascal.session.push')
		self.session_sub = rascal.registry:connect_sub('rascal.session.pub', self)
	end
	
	-- public api
	
	function session_client:create(ttl, session_data)
		return self.session_api:create(ttl, session_data)
	end
	
	function session_client:get(session_id)
		return self.session_api:get(session_id)
	end
	
	function session_client:set_session_data(session_id, session_data)
		self.session_push:set_session_data(session_id, session_data)
	end

	-- proxy validations via the cache
	function session_client:validate(session_id)
		-- check if the session exists in cache
		local session_data = self.cache:get(session_id)
		if session_data then
			-- extend the expiry of the session
			self.session_push:extend(session_id)
			return session_data
		end
		
		-- otherwise check the session server directly
		session_data = self.session_api:validate(session_id)
		if session_data then
			self.cache:push(session_id, session_data)
		end
		return session_data
	end
		
	function session_client:set_value(session_id, key, value)
		self.session_push:set_value(session_id, key, value)
	end
	
	function session_client:extend(session_id, ttl)
		self.session_push:extend(session_id, ttl)
	end
	
	-- subscribe to updates from the main session_server to keep the cache fresh
	
	function session_client:update(session_id, session_data)
		self.cache:push(session_id, session_data)
	end

	function session_client:expire(session_id)
		self.cache:clear(session_id)
	end

end)