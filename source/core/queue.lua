-- fifo queue
-- based on a link list of pairs
-- copyright 2016 Samuel Baird MIT Licence

local class = require("core.class")

local pairs, ipairs = pairs, ipairs

return class(function (queue)
	
	function queue:init()
		self.head = nil
		self.tail = nil
	end
	
	-- push an item to the end of the queue
	function queue:push(item)
		local entry = { item, nil }
		if self.tail then
			self.tail[2] = entry
		else
			self.head = entry
		end
		self.tail = entry
	end
	
	-- pop the oldest item from the front of the queue (or nil)
	function queue:pop(item)
		if self.head then
			local next = self.head[1]
			self.head = self.head[2]
			if self.head == nil then
				self.tail = nil
			end
			return next
		end
		return nil
	end

	function queue:is_empty()
		return self.head == nil
	end
	
end)