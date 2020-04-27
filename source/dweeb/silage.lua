-- provides an in memory set of data objects that can be mostly treated as simple
-- lua tables but are transparently persisted
--
-- tables are wrapped in a metatable to persist and enforce limitattions
-- all keys and values must be bool, number, string or one of these tables
-- 
-- supply a stowage db as the backing store, against a single specified key
--
-- the following normal/idiomatic lua methods cannot be used seamlessly in lua 5.1
-- instead of #, use table:length()
-- instead of pairs(table), use table:pairs()
-- instead of ipairs(table), use table:ipairs()
-- instead of other array/table methods. use table:remove(index) to remove from a table and shuffle down indexes
-- 
-- copyright 2020 Samuel Baird MIT Licence

local class = require('core.class')
local array = require('core.array')

return class(function (silage)
	
	-- inner class to handle wrapped tables
	local silage_table = class(function (silage_table)
		function silage_table:init(silage, entity_id)
			-- private values
			rawset(self, '_silage', silage)
			rawset(self, '_id', entity_id)
			rawset(self, '_data', {})
			rawset(self, '_type', 'empty')	-- empty, array, map
		end
		
		function silage_table:create(initial_values)
			return self._silage:create(initial_values)
		end
		
		function silage_table:unwrap()
			return self._silage:unwrap(self)
		end
		
		function silage_table:push(value)
			if self._type == 'map' then
				error('silage, cannot push values on a map type table')
			end
			
			self[#self._data + 1] = value
		end
		
		silage_table.add = silage_table.push
		
		function silage_table:insert(index, value)
			if self._type == 'map' then
				error('silage, cannot insert values on a map type table')
			end
			
			if self._silage:validate(value) then
				table.insert(self._data, index, value)
				self._silage:persist('insert', self._id, index, value)
			end
		end
		
		function silage_table:remove(index)
			if self._type == 'map' then
				error('silage, cannot remove values on a map type table')
			end

			self._silage:persist('remove', self._id, index)
			table.remove(self._data, index)
		end
		
		-- metatable hooks ---------------------------------------------------------------
		
		function silage_table:__newindex(name, value)
			-- treat tables as either a map or an array in silage for 'reasons'
			if self._type == 'empty' then
				-- find out what kind of table we are
				if name == 1 then
					self._type = 'array'
				else
					self._type = 'map'
				end				
			elseif self._type == 'map' then
				-- anything goes
			elseif self._type == 'array' then
				if name ~= #self._data + 1 then
					error('silage, cannot treat an array type table as a map')
				end
			end
			
			-- do not silently wrap objects as it creates a new object that will no longer match references
			-- but we do need to validate the value is primitive or within the same silage
			if self._silage:validate(name) and self._silage:validate(value) then
				self._silage:persist('set', self._id, name, value)
				self._data[name] = value
			end
		end
		
		function silage_table:__index(name)
			-- handle normal class properties
			if silage_table[name] then
				return silage_table[name]
			end
			
			-- otherwise defer to persistent properties
			if self._data[name] then
				return self._data[name]
			end
		end
				
		function silage_table:__tostring()
			return 'entity:' .. self._id .. ':' .. self._type
		end

		-- stuff we can't properly substitute in lua 5.1 metatables -----------------

		function silage_table:length()
			return #self._data
		end
		
		function silage_table:pairs()
			if self._type == 'array' then
				error('silage, cannot use pairs on an array type table')
			end
			
			return pairs(self._data)
		end
		
		function silage_table:ipairs()
			if self._type == 'map' then
				error('silage, cannot use ipairs on a map type table')
			end
			
			return ipairs(self._data)
		end
		
		function silage_table:iterate()
			if self._type == 'array' then
				return ipairs(self._data)
			else
				return pairs(self._data)
			end
		end
		
		function silage_table:keys()
			-- return an array of all keys, with table objects in order ahead of other properties
			local output = array()
			for k, _ in self:iterate() do
				output:push(k)
			end
			return output
		end
		
		function silage_table:values()
			-- return an array of all values, with table objects in order ahead of other properties
			local output = array()
			for _, v in self:iterate() do
				output:push(v)
			end
			return output		
		end
		
		function silage_table:with_each(fn)
			for _, v in self:iterate() do
				fn(v)
			end
		end
		
		function silage_table:filter(filter_fn)
			local output = array()
			for _, v in self:iterate() do
				if filter_fn(v) then
					output:push(v)
				end
			end
			return output
		end
		
		function silage_table:find(find_fn)
			for i, v in self:iterate() do
				if find_fn(v) then
					return v
				end
			end
		end
		
	end)

	function silage:init(db, db_key)
		-- set up root objects and mappings (avoiding metatable)
		rawset(self, 'db', db)
		rawset(self, 'db_key', db_key)
		rawset(self, 'entities', {})
		rawset(self, 'root', silage_table(self, 1))
		rawset(self, 'last_entity_id', 2)
		self.entities[1] = self.root
		
		-- replay the log to create all entities and load in the required data
		local log_id = 0
		local batch_size = 256
		local function quick_inflate(id)
			local entity = self.entities[id]
			if not entity then
				entity = silage_table(self, id)
				self.entities[id] = entity
				if id > self.last_entity_id then
					self.last_entity_id = id
				end
			end
			return entity
		end
		
		while true do
			local logs = self.db:log_read(self.db_key, log_id, batch_size)
			for _, log in ipairs(logs) do
				-- inflate and assign the objects
				local event = log.data.event
				local id = log.data.id
				local key = log.data.key
				local value = log.data.value
				-- inflate tables to entities
				if type(key) == 'table' then
					key = quick_inflate(key.id)
				end
				if type(value) == 'table' then
					value = quick_inflate(value.id)
				end
				
				local entity = quick_inflate(id)
				if event == 'set' then
					entity._data[key] = value
				elseif event == 'insert' then
					table.insert(entity._data, key, value)
				elseif event == 'remove' then
					table.remove(entity._data, key)
				end
			end
			if #logs < batch_size then
				break
			end
			log_id = logs[#logs].id
		end
		
		-- make the entities table a weak table to allow garbage collection after this point
		setmetatable(self.entities, {
			__mode = 'kv'
		})
	end
	
	-- create and wrap entities --------------------------------------------------------------
	
	function silage:create(initial_values)
		return self:wrap(initial_values or {})
	end
	
	function silage:validate(value)
		local t = type(value)
		if t == 'nil' or t == 'boolean' or t == 'string' or t == 'number' then
			return true
		elseif t == 'table' then
			local meta = getmetatable(value)
			if meta then
				if meta == silage_table then
					if value._silage ~= self then
						error('silage does allow mixing keys and values in different silages')
					end
				else
					error('silage does not support tables with other metatables')
				end
			else
				error('cannot set an unwrapped table')
			end
		end
		return true
	end
	
	function silage:wrap(value, error_level, cycles_table)
		error_level = error_level or 1
		-- absorb cyclic references here by passing through a translation table
		if cycles_table and cycles_table[value] then
			return cycles_table[value]
		end
		
		local t = type(value)
		if t == 'nil' or t == 'boolean' or t == 'string' or t == 'number' then
			return value
		elseif t == 'table' then
			-- check the keys and values of this table recursively
			local meta = getmetatable(value)
			if meta == nil then
				-- create a new entity with this backing and a new entity id
				local next_entity_id = self.last_entity_id + 1;
				self:persist('create', next_entity_id)
				self.last_entity_id = next_entity_id
				local entity = silage_table(self, next_entity_id)
				self.entities[next_entity_id] = entity
				if cycles_table then
					cycles_table[value] = entity
				else
					cycles_table = { value = entity }
				end
				
				-- recursively wrap all the keys and values if we can
				for i, v in ipairs(value) do
					entity[i] = self:wrap(v, error_level + 1, cycles_table)
				end
				for k, v in pairs(value) do
					if type(k) == 'number' and math.floor(k) == k and k >= 1 and k <= #value then
						-- ignore int value keys already traversed
					else
						entity[self:wrap(k, error_level + 1, cycles_table)] = self:wrap(v, error_level + 1, cycles_table)
					end
				end
				return entity
			else
				if meta == silage_table then
					if value._silage == self then
						-- already wrapped and part of this silage
						return value
					else
						error('silage does allow mixing keys and values in different silages', error_level)
					end
				else
					error('silage does not support tables with other metatables', error_level)
				end
			end			
		else
			error('silage does not support ' .. t .. ' keys or values', error_level)		
		end
	end
	
	function silage:unwrap(value, cycles_table)
		local t = type(value)
		if type(value) == 'table' and getmetatable(t) == silage_table then
			-- remap to capture cycles
			if not cycles_table then
				cycles_table = {}
			end
			if cycles_table[value] then
				return cycles_table[value]
			end			
			-- recursively unwrap silage tables to plain tables
			local out = {}
			cycles_table[value] = out
			for k, v in self:iterate() do
				out[self:unwrap(k, cycles_table)] = self:unwrap(v, cycles_table)
			end
			return out
		else
			return value
		end		
	end
	
	-- create and wrap entities --------------------------------------------------------------
	
	function silage:persist(event, id, key, value)
		-- if its a table, it must be an entity, reduce to the id only
		if type(key) == 'table' then
			key = { id = key._id }
		end
		if type(value) == 'table' then
			value = { id = value._id }
		end
		
		-- deflate for persistence
		local entry = {
			event = event,
			id = id,
			key = key,
			value = value
		}		
		self.db:log_append(self.db_key, entry)
	end		
		
	-- mapping to root --------------------------------------------------------------
	
	-- getting or setting arbitrary values gets or sets arbitrary values on the root object
	function silage:__newindex(name, value)
		-- set new values on the root object
		self.root[name] = value
	end
	
	function silage:__index(name)
		-- handle normal class properties
		if silage[name] then
			return silage[name]
		end
		
		-- otherwise redirect to root object
		return self.root[name]
	end
end)