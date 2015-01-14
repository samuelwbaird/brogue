-- the channel cache proxies a channel server into multiple
-- worker threads, reducing communications overhead when polling
-- frequently accessed channels
-- pub/sub with the channel server is used to expire the cache
-- entries and keep data accurate
-- copyright 2014 Samuel Baird MIT Licence

-- core modules
local class = require('core.class')
local array = require('core.array')
local cache = require('core.cache')

local rascal = require('rascal.core')

return class(function (channel_cache)
	local super = channel_cache.new

	function channel_cache.new()
		local self = super()
		-- cache session info in each worker to reduce contention
		self.cache = cache(1024 * 64)
		return self
	end
	
	-- in-process api
	function channel_cache:read(channel)
		-- return tick, status or null
	end
	
	-- subscribe api
	function channel_cache:update(channel, tick_no, status)
	end

end)