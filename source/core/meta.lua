-- common metatable patterns and functionality
-- copyright 2014 Samuel Baird MIT Licence

local module = require('core.module')
local class = require('core.class')
local array = require('core.array')

return module(function (meta)
	
	
	-- return a compound object that reads from a chain of other objects
	function meta.chain(init_item1, init_item2, ...)

		-- recursively add all init items onto the chain
		-- each item in the init list can be either a key value table to add to the chain
		-- or an array in which each entry is added to the chain
		local chain = array()
		local function add_to_chain(init_item1, init_item2, ...)
			if #init_item1 > 0 then
				-- if its an array treat each entry as an item on the chain
				for _, value in ipairs(init_item1) do
					chain:push(value)
				end
			else
				chain:push(init_item1)
			end			
			if init_item2 then
				add_to_chain(init_item2, ...)
			end
		end
		add_to_chain(init_item1, init_item2, ...)
		
		-- return an empty object and metatable to read from the chain until a value is found
		return setmetatable({}, {
			__index = function (proxy, property)
				for _, obj in ipairs(chain) do
					local v = obj[property]
					if v then
						-- store value on the property for subsequent reads
						proxy[property] = v
						-- return the found value
						return v
					end
				end
			end
		})
	end
	
end)
