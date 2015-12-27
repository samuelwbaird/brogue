-- make a compound object from a chain of objects
-- the compound object returns properties from the first object
-- in the chain which has that property
-- copyright 2014 Samuel Baird MIT Licence

local class = require('core.class')
local array = require('core.array')

return class(function (chain)
	
	function chain:init(objects)
		self.objects = objects
	end
	
	function chain:add(obj)
		self.objects[#self.objects + 1] = obj
	end
	
	local super_index = chain.__index
	
	function chain.__index(self, property)
		for _, obj in ipairs(self.objects) do
			local v = obj[property]
			if v then
				return v
			end
		end
		return super_index[property]
	end
end)