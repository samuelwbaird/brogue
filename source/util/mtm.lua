-- many to many dictionary
-- optionally weak
-- any number of keys associated with any number of values
-- set and query by key and clear by value
-- copyright 2014 Samuel Baird MIT Licence

-- API
-- set [keys], value	-- assign a value to an array of keys
-- get key -> [values]	-- get the values associated with a particular key
-- pull key -> [values] -- and remove all references to these values
-- clear key			-- clear any references from this key (does not remove values referenced elsewhere)
-- remove value			-- removes all references to this value

local class = require('core.class')
local array = require('core.array')

return class(function (mtm)
	
	function mtm:init(weak)
		self.by_key = {}
		self.by_value = {}
		self.weak = weak
		if weak then
			setmetatable(self.by_key, {
				__mode = 'k'
			})
			setmetatable(self.by_value, {
				__mode = 'k'
			})
		end
	end
	
	-- internal operations -----------------
	
	local function inverse_set_remove(set, key, inverse_set)
		local ikeys = set[key]
		if not ikeys then
			return
		end
		
		-- remove reference
		set[key] = nil
		
		-- remove reverse references
		for ikey in pairs(ikeys) do
			local values = inverse_set[ikey]
			if values then
				-- remove the referenced value
				values[key] = nil
				-- remove if empty
				if not next(values) then
					inverse_set[ikey] = nil
				end
			end
		end		
	end
	
	local function add_to_set(set, key, value, weak)
		local entry = set[key]
		if not entry then
			entry = {}
			if weak then
				setmetatable(entry, {
					__mode = 'kv'
				})
			end
			set[key] = entry
		end
		entry[value] = value
	end
	
	-- public operations -------------------
	
	function mtm:push(keys, value)
		if type(keys) == 'table' then
			for _, key in ipairs(keys) do
				add_to_set(self.by_key, key, value, self.weak)
				add_to_set(self.by_value, value, key, self.weak)			
			end
		else
			add_to_set(self.by_key, keys, value, self.weak)
			add_to_set(self.by_value, value, keys, self.weak)			
		end
	end
	
	-- returns an array or nil
	function mtm:get(key)
		local out = array()
		local entry = self.by_key[key]
		if entry then
			for k in pairs(entry) do
				out:push(k)
			end
		end
		return out
	end
	
	-- get and remove values
	function mtm:pull(key)
		local result = self:get(key)
		for _, value in ipairs(result) do
			self:remove(value)
		end
		return result
	end
	
	-- remove the key 
	function mtm:clear(key)
		inverse_set_remove(self.by_key, key, self.by_value)
	end
	
	-- remove all references to this value
	function mtm:remove(value)
		inverse_set_remove(self.by_value, value, self.by_key)
	end
	
	-- aliases
	mtm.set = mtm.push
	mtm.put = mtm.push
	mtm.peek = mtm.get
	
end)