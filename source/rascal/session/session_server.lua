-- provides session data to be shared across http workers
-- session data can be persisted with sqlite (or in-memory)
-- provides expiry time with automatically extending ttl
-- works with session_cache to minimise coms
-- copyright 2014 Samuel Baird MIT Licence

local math = require('math')
local os = require('os')

local cmsgpack = require('cmsgpack')

local class = require('core.class')

local rascal = require('rascal.core')
local sqlite = require('dweeb.sqlite')
local random_key = require('rascal.util.random_key')

return class(function (session_server)
	local super = session_server.new

	session_server.api_description = {
		create = 'ttl:int, data:*:optional -> session_id',
		get = 'session_id:string -> session:*',
		validate = 'session_id:string -> session_data:*',
	}

	session_server.push_api_description = {
		set_session_data = 'session_id:string, session_data:*',
		set_value = 'session_id:string, key:string, value:*',
		extend = 'session_id:string, ttl:int:optional',
	}
	
	session_server.pub_api_description = {
		update = 'session_id:string, session_data:*',
		expire = 'session_id',
	}
	
	function session_server.new(db_name, post_channel, api_channel, pub_channel)
		local self = super()
		
		math.randomseed(os.time())
		self.last_purge = nil
		
		-- self.sessions = {}
		self.db = sqlite(db_name, true)
		--self.db:pragma('locking_mode', 'EXCLUSIVE')
		self.db:pragma('synchronous', 'OFF')
		
		self.db:prepare_table('session', {
			columns = {
				{ name = 'session_id', type = 'TEXT UNIQUE' },
				{ name = 'session_data', type = 'TEXT' },
				{ name = 'ttl', type = 'INTEGER' },
				{ name = 'expiry', type = 'INTEGER' },
			},
			indexes = {
				{ columns = { 'expiry' }, type = 'INDEX' }
			},
		})
		
		api_channel = api_channel or 'inproc://rascal.session.api'
		proxy_server(self, session_server.api_description, api_channel, zmq.REP, 'rascal.session.api')

		post_channel = post_channel or 'inproc://rascal.session.push'
		proxy_server(self, session_server.push_api_description, post_channel, zmq.PULL, 'rascal.session.push')
		
		pub_channel = pub_channel or 'inproc://rascal.session.pub'
		self.publish = proxy_server(self, session_server.pub_api_description, pub_channel, zmq.PUB, 'rascal.session.pub')

		-- prepared DB queries
		self.db_check_session_id = self.db:prepare('SELECT COUNT(*) FROM `session` WHERE `session_id` = ? LIMIT 1')
		self.db_insert_session = self.db:insert('session', { 'session_id', 'session_data', 'ttl', 'expiry'}):prepare()
		
		self.db_check_expiring_sessions = self.db:prepare('SELECT `session_id` FROM `session` WHERE `expiry` < ?')
		self.db_expire_sessions = self.db:prepare('DELETE FROM `session` WHERE `expiry` < ?')
		
		self.db_get_session_by_session_id = self.db:prepare('SELECT * FROM `session` WHERE `session_id` = ?')
		
		self.db_set_session_expiry = self.db:update('session', { 'expiry' }, { 'session_id' }):prepare()
		self.db_set_session_data = self.db:update('session', { 'session_data' }, { 'session_id' }):prepare()
		
		return self
	end	
	
	-- internal
	
	function session_server:expiry(ttl)
		return os.time() + (ttl and tonumber(ttl) or 0)
	end
	
	function session_server:purge()
		local now = os.time()
		if (last_purge == nil) or (last_purge < now - 60) then
			-- send clear to caches
			for row in self.db_check_expiring_sessions:query({ now }):rows() do
				self.publish:expire(row.session_id)
			end
			self.db_expire_sessions:execute({ now })
			last_purge = now
		end
	end
	
	-- primary API

	function session_server:create(ttl, session_data)
		self.db:begin_transaction()
		
		local session_id = nil
		while session_id == nil do
			local key = random_key.printable(32)
			if self.db_check_session_id:query({ key }):value() == 0 then
				session_id = key
				break
			end
		end

		-- prepare statement to insert new session
		self.db_insert_session:execute({ session_id, cmsgpack.pack(session_data or {}), ttl, self:expiry(ttl) })
		self.db:commit_transaction()
		
		-- update any other caches
		self.publish:update(session_id, session_data)
		
		return session_id
	end
	
	function session_server:get(session_id)
		local session = self.db_get_session_by_session_id:query({ session_id }):row()
		if session then
			session.session_data = cmsgpack.unpack(session.session_data)
			return session
		else
			return nil
		end
	end
	
	function session_server:validate(session_id)
		self:purge()
		local session = self.db_get_session_by_session_id:query({ session_id }):row()
		if session then
			return cmsgpack.unpack(session.session_data)
		else
			return nil
		end
	end
	
	-- push API
	
	function session_server:set_session_data(session_id, session_data)
		local session = self:get(session_id)
		if session then
			session_data = session_data or {}
			self.db_set_session_data:execute({ cmsgpack.pack(session_data), session_id })
			self.publish:update(session_id, session_data)
		end
	end
	
	function session_server:set_value(session_id, key, value)
		local session = self:get(session_id)
		if session then
			local session_data = session.session_data
			session_data[key] = value
			self.db_set_session_data:execute({ cmsgpack.pack(session_data), session_id })
			self.publish:update(session_id, session_data)
		end		
	end
	
	function session_server:extend(session_id, ttl)
		self:purge()
		local session = self.db_get_session_by_session_id:query({ session_id }):row()
		if session then
			local ttl = ttl or session.ttl
			local new_expiry = self:expiry(ttl)
			-- don't update the expiry if its not that old
			if new_expiry > session.expiry + 10 then
				-- log('extend ' .. session.expiry .. ' ' .. ttl .. ' ' .. self:expiry(ttl))
				self.db_set_session_expiry:execute({ new_expiry, session_id })
			end
		end
	end
	
end)