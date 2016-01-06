-- common metatable patterns and functionality
-- copyright 2016 Samuel Baird MIT Licence

local module = require('core.module')

return module(function (meta)	
	
	function meta.readonly(obj)
		local proxy = {}
		setmetatable(proxy, {
			__index = obj,
			__newindex = function (obj, property, value) error('object is readonly', 2) end
		})
		return proxy
	end
	
	-- wrap an existing index metamethod as a function, regardless of what it currently is
	function meta.wrap_existing_index(metatable)
		local existing_index = metatable.__index
		if existing_index == nil then
			return function () end
		elseif type(existing_index) == 'table' then
			return function (obj, key)
				return existing_index[key]
			end
		else
			return existing_index
		end
	end

	-- wrap an existing newindex metamethod as a function, regardless of what it currently is
	function meta.wrap_existing_newindex(metatable)
		local existing_newindex = metatable.__newindex
		if existing_newindex == nil then
			return function (obj, key, value)
				rawset(obj, key, value)
			end
		elseif type(existing_newindex) == 'table' then
			return function (obj, key, value)
				existing_newindex[key] = value
			end
		else
			return existing_newindex
		end
	end
	
	-- invoke an index handler prior to the current metatables handler
	-- index_handler(obj, property, existing_handler) -> true, value if handled
	function meta.intercept_index(metatable, index_handler)
		local existing = meta.wrap_existing_index(metatable)
		metatable.__index = function (obj, property)
			local handled, value = index_handler(obj, property, existing)
			if handled then
				return value
			end
			return existing(obj, property)
		end		
	end
	
	-- intercept_newindex return true if intercepted
	-- newindex_handler(obj, property, value, existing_handler) -> true if handled
	function meta.intercept_newindex(metatable, newindex_handler)
		local existing = meta.wrap_existing_newindex(metatable)
		metatable.__newindex = function (obj, property, value)
			local handled = newindex_handler(obj, property, value, existing)
			if not handled then
				existing(obj, property, value)
			end
		end
	end
	
	-- return a compound object that reads from a chain of other objects
	function meta.read_proxy_chain(init_item1, init_item2, ...)
		-- recursively add all init items onto the chain
		-- each item in the init list can be either a key value table to add to the chain
		-- or an array in which each entry is added to the chain
		local chain = {}
		local function add_to_chain(init_item1, init_item2, ...)
			if #init_item1 > 0 then
				-- if its an array treat each entry as an item on the chain
				for _, value in ipairs(init_item1) do
					chain[#chain + 1] = value
				end
			else
				chain[#chain + 1] = init_item1
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
