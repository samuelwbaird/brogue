-- multiple most recently used list
-- fixed size, discard oldest
-- stores multiple values for each key but honours recent list per individual entry
-- copyright 2016 Samuel Baird MIT Licence

-- API
-- put key, value -> discarded value if applicable by order (not key)
-- pull key -> [values] and remove from cache
-- peek key -> [values]

local class = require('core.class')
local array = require('core.array')

return class(function (mmru)

	function mmru:init(retain_size)
		self.retain_size = tonumber(retain_size) or 1024
		
		-- hard mmru, simple ring buffer for each access
		self.ring_buffer = {}
		self.ring_buffer_index = 0
		
		-- reverse access from key to ring buffer entry
		self.reverse = {}
	end
	
	function mmru:push(key, value)
		local return_value = nil
		
		-- set up the multiple list of entries for this key
		local entries = self.reverse[key]
		if not entries then
			entries = {}
			self.reverse[key] = entries
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
			-- remove the entry for the reverse index
			local evicted_key = entry[1]
			if evicted_key then
				local reverse_entries = self.reverse[evicted_key]
				if reverse_entries then
					reverse_entries[self.ring_buffer_index] = nil
					-- clean up empty reverse entries
					if not next(reverse_entries) and key ~= evicted_key then
						self.reverse_entries[evicted_key] = nil
					end
				end
			end
			-- reuse the entry
			entry[1] = key
			entry[2] = value
		else
			-- set a new value in the ring buffer
			entry = { key, value }
			self.ring_buffer[self.ring_buffer_index] = entry
		end

		-- update the multiple reverse index
		entries[self.ring_buffer_index] = entry
		
		-- return the evicted value if we found one
		return return_value
	end
	
	-- get the value for a key
	function mmru:get(key)
		local entries = self.reverse[key]
		if entries then
			local output = array()
			for index, entry in pairs(entries) do
				if entry and entry[2] then
					output:push(entry[2])
				end
			end
			return output
		end
	end
	
	-- get and clear
	function mmru:pull(key)
		local value = self:get(key)
		if value then
			self:clear(key)
		end
		return value
	end
	
	-- remove the key and its entry
	function mmru:clear(key)
		local entries = self.reverse[key]
		if entries then
			self.reverse[key] = nil
			for index, _ in pairs(entries) do
				self.ring_buffer[index] = nil
			end
		end
	end
	
	mmru.set = mmru.push
	mmru.put = mmru.push
	mmru.peek = mmru.get
	
end)