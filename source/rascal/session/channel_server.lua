-- a channel is a stream of events and latest state
-- channels are a way to capture the internal (complete) state of a simulation
-- as a streamed view (coherent) that can be externalised
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
-- there are different ways by which to organise and update the stream
-- depending what is appropriate for the data in that stream
--
-- copyright 2014 Samuel Baird MIT Licence

local class = require('core.class')

local rascal = require('rascal.core')
local sqlite = require('dweeb.sqlite')

return class(function (channel_server)
	local super = channel_server.new

	-- update or read from the 
	channel_server.api_description = {
		read = 'channel:string, tick:int:optional -> response:*',	-- response may include status+event data
	}
	
	-- pull a single source of event updates from the main simulation
	channel_server.push_api_description = {
		tick = '',																		-- expire events
		push = 'channel:string, status_data:*, event_data:*, ttl:int, filter:string'	-- push a new event to a channel
	}
	
	-- publish updates to co-ordinate with in-process cache objects
	channel_server.pub_api_description = {
		update = 'channel:string, tick_no:int, state:*',			-- publish the current tick no and state for a particular channel
	}
	
--[[
-- server dynamic view

-- optional cache view to hold at the worker end and use pub/sub to retain?
-- everything? or just latest world data and tick number?
-- just latest tick might be the most appropriate to avoid sending out of sequence world state, just defer to long poll instead of poll
-- could also hang a callback function on the cache object to callback on updates that should trigger 
-- a signal of a deferred connections

-- internal cache for latest tick number and world state on each channel to avoid hitting the db?

-- view type eg. location, player, world, event
-- view id eg. player1
-- combines latest state with TTL'd and filtered events
-- all timestamps are just a tick number
-- lookup with no tick and get latest state + latest tick number
-- lookup with a tick number and get latest state + all events since that tick number still on record

-- defined on the server
-- potentially supply a function to rebuild the latest state with every event pushed
-- database backed, retain all events with ttl, retain latest state, unless its defined lazily
-- database could be in memory only, but db indexing will be best for tick ttl expiring

-- options for updates
-- 1. server can push to a stream event + state
-- 2. at define time include a function to recreate state, and just push event, state recreated as required (each push invalidates previous)
--   eg. stream = world_view_stream('location', get_location_state) -- callback to get latest state
--       stream:push(event, true) -- push event and invalidate state
-- 3. push an event and supply a function to mutate the existing state
--   eg. location:push(player_leaves_event, remove_player)
-- 4. push an event without an update to state? so the previous state still stands and must be transmitted along with subsequent events
--   the api format for returned data will need to distinguish where the world state comes in the sequence of events transmitted


]]
	
	function channel_server.new(db_name, push_channel, api_channel, pub_channel)
		local self = super()
		self.db = sqlite(db_name, true)
		self.db:pragma('synchronous', 'OFF')
		
		self.db:prepare_table('status', {
			columns = {
				{ name = 'channel', type = 'TEXT UNIQUE' },
				{ name = 'status_data', type = 'TEXT' },
			},
		})
		
		self.db:prepare_table('event', {
			columns = {
				{ name = 'channel', type = 'TEXT' },
				{ name = 'tick', type = 'INTEGER' },
				{ name = 'expiry', type = 'INTEGER' },
				{ name = 'filter', type = 'TEXT' },
				{ name = 'event_data', type = 'TEXT' },
			},
			indexes = {
				{ columns = { 'channel', 'tick' }, type = 'INDEX' },
				{ columns = { 'channel', 'filter' }, type = 'INDEX' },
				{ columns = { 'expiry' }, type = 'INDEX' },
			},
		})
		
		-- set the initial tick to the highest existing tick number + 1
		-- self.tick = 
		
		-- internal cache of the status table?
		
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
		self.tick = self.tick + 1
		-- expire all events older than tick
	end
	
	function channel_server:push(channel, status_data, event_data, ttl, filter)
		
		self.publish:update(channel, self.tick, status_data)
	end
	
	-- req API -----------------
	
	function channel_server:read(channel, tick)
	end
	
end)