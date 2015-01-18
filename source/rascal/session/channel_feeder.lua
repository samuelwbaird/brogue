-- copyright 2014 Samuel Baird MIT Licence

-- TODO: investigate "typed" channels where each channel type
-- can have rules associated to generate full status events as required
-- or automatic coalescing events after updates or timeouts

-- core modules
local class = require('core.class')
local array = require('core.array')
local cache = require('core.cache')

local rascal = require('rascal.core')

return class(function (channel_feeder)
	local super = channel_feeder.new

	function channel_feeder.new()
		local self = super()
		self.cache = cache(1024 * 64)
		self.channels_push = rascal.registry:connect('rascal.channels.push')
		self.batch = nil
		return self
	end
	
	-- external API ------------------------------
	
	function channel_feeder:push(channel, type, data, ttl, filter)
		if self.batch then
			self.batch:push({
				channel = channel,
				type = type,
				data = data,
				ttl = ttl,
				filter = filter,
			})
		else
			self.channels_push:push(channel, type, data, ttl, filter)
		end
	end
	
	function channel_feeder:tick()
		self.channels_push:tick()
	end

	function channel_feeder:begin_batch()
		if self.batch == nil then
			self.batch = array()
		end
	end
	
	function channel_feeder:cancel_batch()
		self.batch = nil
	end
	
	function channel_feeder:commit_batch()
		if self.batch ~= nil then
			self.channels_push:push_batch(self.batch)
			self.batch = nil
		end
	end	
	

end)