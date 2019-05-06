-- a general purpose in-memory cache to layer over slower storage like DBs
-- each cache entry is stored against one key, but can have an optional list of
-- additional keys used to trigger invalidation
--
-- copyright 2019 Samuel Baird MIT Licence

local class = require('core.class')
local array = require('core.array')

return class(function (silage)
	
	function silage:init(retain_count)
		-- weak cache of all values
		self.weak = setmetatable({}, {
			__mode = 'kv'
		})
		
		-- reference each cache entry from a number of keys that can be used to invalidate it
		self.invalidation_keys = setmetatable({}, {
			__mode = 'kv'
		})
		
		-- ring buffer to force a certain recently used number to be retained
		if retain_count then
			self.ring_buffer = {}
			self.ring_buffer_index = 0
			self.retain_count = retain_count
		end
	end	
	
	function silage:sile(key, value_function, invalidation_keys)
		local value = self:peak(key)
		if not value then
			value = value_function()
			self:store(key, value, invalidation_keys)
		end
		return value
	end
	
	function silage:store(key, value, invalidation_keys)
		self:clear(key)
		local entry = {
			key = key,
			value = value,
			invalidation_keys = invalidation_keys
		}
		self.weak[key] = entry
		
		-- store in ring buffer to force retain		
		if self.ring_buffer then
			self.ring_buffer_index = self.ring_buffer_index + 1
			if self.ring_buffer_index > self.retain_count then
				self.ring_buffer_index = 1
			end
			self.ring_buffer[self.ring_buffer_index] = entry
		end
		
		-- add to the list of invalidation key entries pointing back at actual entries
		for _, invalidation_key in ipairs(invalidation_keys) do
			local entries = self.invalidation_keys[key]
			if not entries then
				entries = setmetatable({}, {
					__mode = 'kv'
				})
				self.invalidation_keys[key] = entries
			end
			entries[entry] = entry
		end
	end
	
	function silage:peak(key)
		local entry = self.weak[key]
		if entry then
			return entry.value
		end
		return nil
	end
	
	function silage:invalidate(invalidation_key)
		local entries = self.invalidation_keys[key]
		if entries then
			for entry in ipairs(entries) do
				self.weak[entry.key] = nil
			end
			self.invalidation_keys[key] = nil
		end
	end
	
	function silage:clear(key)
		local entry = self.weak[key]
		if entry then
			self.weak[key] = nil
			if entry.invalidation_keys then
				for _, key in ipairs(entry.invalidation_keys) do
					local entries = self.invalidation_keys[key]
					if entries then
						entries[entry] = nil
					end
					if not next(entries) then
						self.invalidation_keys[key] = nil
					end
				end
			end
		end
	end
	
end)