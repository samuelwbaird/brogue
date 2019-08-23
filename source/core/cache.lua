-- simple cache module based on a ring buffer
-- most basic approach, double entries are not collated
-- weak references are reused until collected
-- copyright 2016 Samuel Baird MIT Licence

local class = require('core.class')

return class(function (cache)

	function cache:init(retain_size)
		self.retain_size = tonumber(retain_size) or 0
		self:clear()
	end
	
	function cache:push(key, value)
		self.weak[key] = value
		self:retain(key, value)
		return value
	end
	
	function cache:clear(key)
		if key then
			self.weak[key] = nil
		else
			-- weak cache of all values
			self.weak = setmetatable({}, {
				__mode = 'kv'
			})
			-- hard cache, simple ring buffer for each access
			-- this means double access is represented twice which might be good or bad
			self.ring_buffer = {}
			self.ring_buffer_index = 0
		end
	end
	
	cache.set = cache.push
	
	function cache:get(key)
		local value = self.weak[key]
		if value then
			self:retain(key, value)
		end
		return value
	end
	
	function cache:get_or_set(key, create_function, ...)
		local value = self.weak[key]
		if value then
			self:retain(key, value)
			return value
		end
		return self:push(key, create_function(...))
	end
	
	function cache:peek(key)
		return self.weak[key]
	end
	
	function cache:retain(key, value)
		if self.retain_size > 0 then
			self.ring_buffer_index = self.ring_buffer_index + 1
			if self.ring_buffer_index > self.retain_size then
				self.ring_buffer_index = 1
			end
			self.ring_buffer[self.ring_buffer_index] = { key, value }
		end
	end
	
end)