-- the channel cache proxies a channel server into multiple
-- worker threads, reducing communications overhead when polling
-- frequently accessed channels
-- pub/sub with the channel server is used to expire the cache
-- entries and keep data accurate
-- copyright 2014 Samuel Baird MIT Licence

-- TODO: at some point consider implementing filter and expiry rules here so an up to date
-- set of events can be maintained without doing a clear cache and full read each time, may
-- be of only marginal benefit, may avoid lots of blocking read calls

-- core modules
local class = require('core.class')
local array = require('core.array')
local cache = require('core.cache')

local rascal = require('rascal.core')

return class(function (channel_cache)
	local super = channel_cache.new

	function channel_cache.new(on_update)
		local self = super()
		self.cache = cache(1024 * 64)

		-- connect to the channel server
		self.channels_api = rascal.registry:connect('rascal.channels.api')
		self.channels_sub = rascal.registry:connect_sub('rascal.channels.pub', self)

		-- call back when updates come in
		self.on_update = on_update	-- on_update(channel, last_event_id)
		return self
	end
	
	-- in-process api
	
	function channel_cache:read(channel, last_seen_event_id)
		last_seen_event_id = last_seen_event_id or 0

		-- check for a cached data
		local data = self.cache:get(channel)

		-- if no cached data then hit the server
		if not data then
			-- read the full data from the server, to share requests with differing history lengths
			data = self.channels_api:read(channel)
			self.cache:set(channel, data)
		end
		
		-- filter events here
		local filtered = array()
		for _, event in ipairs(data.events) do
			if event.id > last_seen_event_id then
				filtered:push(event)
			end
		end
		
		-- return filtered version
		return {
			current_tick = data.current_tick,
			last_event_id = data.last_event_id,
			events = filtered
		}
	end
	
	-- subscribe api
	
	function channel_cache:did_expire(channel, tick)
		-- TODO: instead of clearing cache could filter channel data here
		-- TODO: this requires replicating the expiry rules correctly here
		
		self.cache:clear(channel)
	end
	
	function channel_cache:did_update(channel)
		-- TODO: instead of clearing cache, if present could mark as old and only read updated data next time
		-- TODO: this requires replicating the filter rules correctly here

		self.cache:clear(channel)
		-- callback if required eg. to trigger long poll signals
		if self.on_update then
			self.on_update(channel)
		end
	end

end)