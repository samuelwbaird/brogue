-- a channel is a stream of events
-- the channel captures a dilated "now" that can be externalised
--
-- channels can be defined arbitrariy, with a string name
-- events posted to channel live for a number of ticks, the server
-- must be ticked manually to retire expired events
--
-- it is expected that the channel server will be used along with the 
-- channel cache to support long polling
-- channels run in their own process to avoid blocking on the main thread
-- to read status or push events
--
-- copyright 2014 Samuel Baird MIT Licence

local cmsgpack = require('cmsgpack')

local class = require('core.class')

local rascal = require('rascal.core')
local cache = require('core.cache')
local sqlite = require('dweeb.sqlite')

return class(function (channel_server)
	local super = channel_server.new

	-- update or read from the 
	channel_server.api_description = {
		read = 'channel:string, last_seen_event_id:int:optional -> events:*',	-- include events and current tick no
	}
	
	-- pull a single source of event updates from the main simulation
	channel_server.push_api_description = {
		tick = '',															-- expire events
		push = 'channel:string, type:*, data:*, ttl:int, filter:string',	-- push a new event to a channel
		push_batch = 'events:*',											-- push a batch of events { channel, type, data, ttl, filter }
	}
	
	-- publish updates to co-ordinate with in-process cache objects
	channel_server.pub_api_description = {
		did_expire = 'channel:string, tick:int',	-- signal that data in a channel was expired
		did_update = 'channel:string',				-- publish that a channel has updated
	}
	
	function channel_server.new(db_name, push_channel, api_channel, pub_channel)
		local self = super()
		self.db = sqlite(db_name, true)
		self.db:pragma('synchronous', 'OFF')
		
		-- store last tick in a table somewhere
		self.db:prepare_table('config', {
			columns = {
				{ name = 'current_tick', type = 'INTEGER' },
			},
			indexes = {
			},
		})
		
		self.db:prepare_table('event', {
			columns = {
				{ name = 'id', type = 'INTEGER PRIMARY KEY AUTOINCREMENT' },
				{ name = 'channel', type = 'TEXT' },
				{ name = 'expiry', type = 'INTEGER' },
				{ name = 'filter', type = 'TEXT' },
				{ name = 'type', type = 'TEXT' },
				{ name = 'data', type = 'TEXT' },
			},
			indexes = {
				{ columns = { 'channel', 'id' }, type = 'INDEX' },
				{ columns = { 'channel', 'filter' }, type = 'INDEX' },
				{ columns = { 'expiry' }, type = 'INDEX' },
			},
		})
		
		local config = self.db:select('config', '*'):query():row()
		if config then
			-- get up to date with latest config
			self.current_tick = config.current_tick
		else
			-- set up default config
			self.current_tick = 1
			self.db:insert('config', { current_tick = self.current_tick }):execute()
		end
		
		-- cache the last event id and increment and set manually?
		local last_row = self.db:select('event', 'id'):order_by('id', 'DESC'):limit(1):query():row()
		self.last_event_id = last_row and last_row.id or 0
		
		-- prepared db statements
		self.sql_update_current_tick = self.db:update('config', { 'current_tick' }):prepare()

		self.sql_insert_event = self.db:insert('event', { 'id', 'channel', 'expiry', 'filter', 'type', 'data' }):prepare()
		self.sql_get_events = self.db:prepare('SELECT * FROM `event` WHERE `channel` = ? AND `id` > ?')
		self.sql_check_expiring = self.db:prepare('SELECT `channel` FROM `event` WHERE `expiry` < ? AND `expiry` > 0')
		self.sql_expire_events = self.db:prepare('DELETE FROM `event` WHERE `expiry` < ? AND `expiry` > 0')
		self.sql_filter_events = self.db:delete('event', { 'channel', 'filter' }):prepare()

		-- publish apis
		
		api_channel = api_channel or 'inproc://rascal.channels.api'
		proxy_server(self, channel_server.api_description, api_channel, zmq.REP, 'rascal.channels.api')

		push_channel = push_channel or 'inproc://rascal.channels.push'
		proxy_server(self, channel_server.push_api_description, push_channel, zmq.PULL, 'rascal.channels.push')
		
		pub_channel = pub_channel or 'inproc://rascal.channels.pub'
		self.publish = proxy_server(self, channel_server.pub_api_description, pub_channel, zmq.PUB, 'rascal.channels.pub')
		
		return self
	end	
	
	-- push API --------------
	
	function channel_server:tick()
		self.current_tick = self.current_tick + 1
		self.sql_update_current_tick:execute({ self.current_tick })
		
		-- check what should be expired
		local channels = {}
		for row in self.sql_check_expiring:query({ self.current_tick }):rows() do
			channels[row.channel] = true
		end
		
		-- expire the events
		self.sql_expire_events:execute({ self.current_tick })
		
		-- signal the change in data
		for channel in pairs(channels) do
			self.publish:did_expire(channel, self.current_tick)
		end
	end
	
	function channel_server:push(channel, type, data, ttl, filter)
		self:add_event(channel, type, data, ttl, filter)
		self.publish:did_update(channel)
	end
	
	function channel_server:push_batch(events)
		-- build a list of all channels updated to publish
		local channels = {}

		-- update the batch
		self.db:transaction(function (self)
			for _, event in ipairs(events) do
				channels[event.channel] = true
				self:add_event(event.channel, event.type, event.data, event.ttl, event.filter)
			end
		end, self)
		
		-- notify once per channel
		for channel in pairs(channels) do
			self.publish:did_update(channel)
		end
	end	
	
	function channel_server:add_event(channel, type, data, ttl, filter)
		-- filter if require
		if filter and filter ~= '' then
			self.sql_filter_events:execute({ channel, filter })
		end
		
		local expiry = ttl and (self.current_tick + ttl) or 0

		self.last_event_id = self.last_event_id + 1
		self.sql_insert_event:execute({
			self.last_event_id,
			channel,
			expiry,
			filter,
			type,
			cmsgpack.pack(data),
		})
	end
	
	-- req API -----------------
	
	function channel_server:read(channel, last_seen_event_id)
		last_seen_event_id = last_seen_event_id or 0
		local out = {
			current_tick = self.current_tick,
			last_event_id = self.last_event_id
		}
		local events = {}
		
		local query = self.sql_get_events:query({ channel, last_seen_event_id })
		for row in query:rows() do
			events[#events + 1] = {
				id = row.id,
				type = row.type,
				expiry = row.expiry,
				filter = row.filter,
				data = cmsgpack.unpack(row.data),
			}
		end
		out.events = events
		
		return out
	end
	
end)