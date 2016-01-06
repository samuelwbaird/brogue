-- most recently used list
-- fixed size, discard oldest
-- only most recent is held
-- copyright 2016 Samuel Baird MIT Licence

-- API
-- put key, value -> discarded value if applicable (discard by order and by duplicate key?)
-- pull key -> value and remove from cache
-- peek key -> value

local class = require('core.class')

return class(function (mru)

	function mru:init(retain_size)
		self.retain_size = tonumber(retain_size) or 1024
		-- hard mru, simple ring buffer for each access
		self.ring_buffer = {}
		self.ring_buffer_index = 0
		-- reverse access from key to ring buffer entry
		self.reverse = {}
	end
	
	function mru:push(key, value)
		local return_value = nil
		
		-- clear any double entry
		local existing = self.reverse[key]
		if existing then
			self.ring_buffer[existing] = nil
		end
		
		-- update the ring buffer
		self.ring_buffer_index = self.ring_buffer_index + 1
		if self.ring_buffer_index > self.retain_size then
			self.ring_buffer_index = 1
		end
		local entry = self.ring_buffer[self.ring_buffer_index]
		if entry then
			-- return the evicted value
			return_value = entry[2]
			-- reuse and clear reverse
			self.reverse[entry[1]] = nil
			entry[1] = key
			entry[2] = value
		else
			self.ring_buffer[self.ring_buffer_index] = { key, value }
		end

		-- reverse index for lookup and cleanup
		self.reverse[key] = self.ring_buffer_index
		
		-- return the evicted value if we found one
		return return_value
	end
	
	-- get the value for a key
	function mru:get(key)
		local existing = self.reverse[key]
		if existing then
			local entry = self.ring_buffer[existing]
			return entry and entry[2]
		end
	end
	
	-- get and clear
	function mru:pull(key)
		local existing = self.reverse[key]
		if not existing then
			return nil
		end

		local entry = self.ring_buffer[existing]
		self.reverse[key] = nil
		self.ring_buffer[existing] = nil
		return entry and entry[2]
	end
	
	-- remove the key and its entry
	function mru:clear(key)
		local existing = self.reverse[key]
		if existing then
			self.reverse[key] = nil
			self.ring_buffer[existing] = nil
		end
	end
	
	mru.set = mru.push
	mru.put = mru.push
	mru.peek = mru.get
	
end)