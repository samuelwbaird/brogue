-- a collection to store items against a number of ticks after which they signal
-- has reverse look up table so frequent and arbitrary adds and removes should be handled well enough
-- copyright 2016 Samuel Baird MIT Licence

local class = require('core.class')

return class(function (timeout_group)
	
	function timeout_group:init()
		self:clear()
	end
	
	function timeout_group:add(obj, ticks)
		if not ticks or ticks < 0 then
			assert(ticks and ticks >= 0)
		end
		
		local tick = self.tick + ticks
		local group = self.groups[tick]
		if not group then
			group = {}
			self.groups[tick] = group
		end
		
		group[obj] = obj
		self.reverse[obj] = group
	end
	
	function timeout_group:remove(obj)
		local group = self.reverse[obj]
		if group then
			self.reverse[obj] = nil
			group[obj] = nil
		end
	end
	
	function timeout_group:clear()
		self.tick = 0
		self.groups = {}
		-- weakly reference reverse look up
		self.reverse = setmetatable({}, {
			__mode = 'kv'
		})
	end
	
	function timeout_group:update(with_ready)
		self.tick = self.tick + 1
		local group = self.groups[self.tick]
		if group then
			-- clean up
			self.groups[self.tick] = nil
			for k, v in pairs(group) do
				self.reverse[k] = nil
			end
			-- then callback on objects that are ready
			for k, v in pairs(group) do
				with_ready(k)
			end
		end
	end
	
end)