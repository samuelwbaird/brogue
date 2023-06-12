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
-- copyright 2022 Samuel Baird MIT Licence

-- silage 			(an object world)
-- silage_table		(presents as a enhanced lua table that automatically persists itself)
-- silage_backing	(backing store interface required by each object world)

-- each silage world has a root silage_table, and will map properties and methods to that root by default
-- each silage also must have a silage_backing backing store

-- all update/log entry types
-- map		(map_id)
-- array	(array_id)
-- set		(map_id|array_id, field, value)
-- insert	(array_id, index, value)
-- remove	(array_id, index)

-- interface, silage world root
local silage_interface = {
	silage = function (silage_backing) end,	-- construct a silage world with a silage backing
	silage = function (db, db_key) end,		-- or provide a stowage db and key, to provide the default stowage backing

	create = function (optional_initial_values) end,	-- create a new silage table within the silage world, with optional initial values
	wrap = function (lua_value) end,		-- wrap any valid value for silage
	unwrap = function () end,				-- take an silage table and produce an 'unwrapped' version, a non-silage, copy of the object tree
	validate = function (lua_value) end,	-- check if a value can be persisted (ie. primitive value, or table without metadata)

	rewrite_log = function () end,			-- rewrites a fresh version of the log based on the current object state only (could be long running)
}

-- interface, silage_table
local silage_table_interface = {
	create = function (initial_values) end,		-- proxied to the silage root
	wrap = function (table) end,				-- proxied to the silage root
	unwrap = function () end,					-- proxied to the silage root, unwrap with this table as the root of the output object

	array = function (name) end,				-- create or retrieve a subobject with this property name or an array type
	map = function (name, initial_values) end,	-- create or retrieve a subobject with this property name or a map type

	-- array functions
	push = function (primitive_or_silage_value) end,	-- add a new value to the end of an array
	push_wrap = function (lua_value) end,		-- wrap a lua_value into a new silage value and push it
	add = function (value) end,					-- alias of push
	insert = function (index, value) end,		-- insert a value into an array at a specified index
	remove = function (index) end,				-- remove the value at a specified index (and compact down)
	length = function () end,					-- return the length of the array
	ipairs = function () end,					-- return an ipairs iterator for the array content
	remove_where = function (filter_fn) end,	-- remove entries in the array for which the filter function returns true

	-- map functions
	pairs = function () end,					-- return a pairs iterator the the map content

	-- works with arrays and maps
	iterate = function () end,					-- return either an ipairs or pairs iterator depending on the type of table
	keys = function () end, 					-- return an array of all keys, with table objects in order ahead of other properties
	values = function () end, 					-- return an array of all values, with table objects in order ahead of other properties
	with_each = function (fn) end,				-- call a function with every value in the table
	is_empty = function () end,					-- return true if the table has no values set
	has = function (key) end,					-- return true if the key has a value
	index_of = function (value) end,			-- return the first key/index for a value (if any)
	find = function (find_fn) end,				-- returns the first value for which the fn returns true
	find_all = function (filter_fn) end,		-- returns an array of all values for which the fn returns true
}

-- interface, silage backing
local silage_backing_interface = {
	log_append = function (data) end,						-- append to the history log for this silage
	log_read = function (from_log_id, max_batch_size) end,	-- read from the history log (in batches)
	log_clear = function () end,							-- clear the entire history log
	transaction = function (fn_operations) end,				-- perform
}

local class = require('core.class')
local array = require('core.array')

-- marker object to indicate empty table that should be treated as an array
local create_as_empty_array = {}

-- silage table, each table value within a silage root
local silage_table = class(function (silage_table)
	function silage_table:init(silage, entity_id, type)
		-- private values
		rawset(self, '_silage', silage)
		rawset(self, '_id', entity_id)
		rawset(self, '_data', {})
		rawset(self, '_type', type or 'map')	-- array, map
		rawset(silage.entities, entity_id, self)
	end

	function silage_table:create(initial_values)
		return self._silage:wrap(initial_values or {})
	end

	function silage_table:array(name)
		if not name then
			return self._silage:wrap(create_as_empty_array)
		end

		local array = self._data[name]
		if array then
			if array._type == 'map' then
				error('silage, cannot treat ' .. name .. ' as array', 2)
			end
		else
			array = self._silage:wrap(create_as_empty_array)
			self[name] = array
		end
		return array
	end

	function silage_table:map(name)
		if not name then
			return self._silage:wrap({})
		end

		local map = self._data[name]
		if map then
			if map._type == 'array' then
				error('silage, cannot treat ' .. name .. ' as map', 2)
			end
		else
			map = self._silage:wrap({})
			self[name] = map
		end
		return map
	end

	function silage_table:wrap(table)
		return self._silage:wrap(table)
	end

	function silage_table:unwrap()
		return self._silage:unwrap(self)
	end

	function silage_table:push(value)
		if self._type == 'map' then
			error('silage, cannot push values on a map type table', 2)
		end

		self[#self._data + 1] = value
	end

	function silage_table:push_wrap(value)
		self:push(self:wrap(value))
	end

	silage_table.add = silage_table.push

	function silage_table:insert(index, value)
		if self._type == 'map' then
			error('silage, cannot insert values on a map type table', 2)
		end

		if self._silage:validate(value) then
			table.insert(self._data, index, value)
			self._silage:persist('insert', self._id, index, value)
		end
	end

	function silage_table:remove(index)
		if self._type == 'map' then
			error('silage, cannot remove values on a map type table', 2)
		end

		self._silage:persist('remove', self._id, index)
		table.remove(self._data, index)
	end

	function silage_table:clear()
		if self._type == 'map' then
			for k, v in self:iterate() do
				self[k] = nil
			end
		else
			for n = self:length(), 1, -1 do
				self:remove(n)
			end
		end
	end

	-- resuse all values possible, while setting state to match another object
	function silage_table:merge_set(target, merge_using_id, delete_unused)
		-- if target is a silage table then don't allow that yet
		if getmetatable(target) == silage_table then
			error('merge_set from other silage tables is not yet supported', 2)
		end

		if self._type == 'map' then
			-- set all keys to use values
			for k, v in pairs(target) do
				if type(self[k]) == 'table' and type(v) == 'table' then
					-- recursive merge
					self[k]:merge_set(v, merge_using_id, delete_unused)
				elseif type(v) == 'table' then
					-- merge into a new object
					self[k] = self:wrap(v)
				else
					self[k] = v
				end
			end
			-- delete all unused keys
			if delete_unused then
				for k, v in self:iterate() do
					if type(target[k]) == 'nil' then
						self[k] = nil
					end
				end
			end
		else
			-- keep track of any previous values we can reuse
			local previous_values = self:values()
			local previous_mapped = {}
			if merge_using_id then
				previous_values:with_each(function (e)
					previous_mapped[e.id] = e
				end)
			end
			
			for i, v in ipairs(target) do
				-- find matching sub objects by ID if applicable
				local existing = previous_values[i]
				if merge_using_id then
					existing = previous_mapped[v.id]
				end
				-- recursive merge if needed
				if type(existing) == 'table' and type(v) == 'table' then
					existing:merge_set(v, merge_using_id, delete_unused)
					self[i] = existing
				elseif type(v) == 'table' then
					-- merge into a new object
					self[i] = self:wrap(v)
				else
					self[i] = v
				end
			end
			
			if delete_unused then
				while self:length() > #target do
					self:remove(self:length())
				end
			end
		end
	end

	-- metatable hooks ---------------------------------------------------------------

	function silage_table:__newindex(name, value)
		-- ignore if nothing has changed
		if self._data[name] == value then
			return
		end

		-- treat tables as either a map or an array in silage for 'reasons'
		if self._type == 'map' then
			-- anything goes
		elseif self._type == 'array' then
			if name ~= #self._data + 1 then
				error('silage, cannot treat an array type table as a map', 2)
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

	function silage_table:is_empty()
		return next(self._data) == nil
	end

	function silage_table:pairs()
		if self._type == 'array' then
			error('silage, cannot use pairs on an array type table', 2)
		end

		return pairs(self._data)
	end

	function silage_table:ipairs()
		if self._type == 'map' then
			error('silage, cannot use ipairs on a map type table', 2)
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

	function silage_table:iterate_random()
		local keys = {}
		for k, _ in self:iterate() do
			keys[#keys + 1] = k
		end
		return function ()
			if #keys == 0 then
				return
			end
			local index = math.random(1, #keys)
			local key = keys[index]
			table.remove(keys, index)
			return key, self._data[key]
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

	function silage_table:has(key)
		return type(self._data[key]) ~= 'nil'
	end

	function silage_table:find(find_fn)
		for i, v in self:iterate() do
			if find_fn(v) then
				return v
			end
		end
	end

	function silage_table:find_all(filter_fn)
		local output = array()
		for _, v in self:iterate() do
			if filter_fn(v) then
				output:push(v)
			end
		end
		return output
	end

	function silage_table:random_element()
		if self:is_empty() then
			return nil
		end

		if self._type == 'array' then
			return self._data[math.random(1, #self._data)]
		else
			return self:values():random_element()
		end
	end

	function silage_table:transform_values(transform_fn)
		local out
		if self._type == 'array' then
			out = array()
		else
			out = {}
		end
		for k, v in self:iterate() do
			out[k] = transform_fn(v)
		end
		return out
	end

	-- count (where meets predicate)
	function silage_table:count(filter_fn)
		local count = 0
		for _, v in self:iterate() do
			if (filter_fn == nil) or filter_fn(v) then
				count = count + 1
			end
		end
		return count
	end

	function silage_table:sum(filter_fn)
		local count = 0
		for _, v in self:iterate() do
			if filter_fn then
				local result = filter_fn(v)
				if tonumber(result) then
					count = count + tonumber(result)
				elseif result then
					count = count + 1
				end
			else
				count = count + (tonumber(v) or 0)
			end
		end
		return count
	end

	function silage_table:index_of(value)
		for i, v in self:iterate() do
			if v == value then
				return i
			end
		end
	end

	function silage_table:remove_where(filter_fn)
		if self._type == 'map' then
			error('silage, cannot remove values on a map type table', 2)
		end

		local index = 1
		local length = self:length()

		while index <= length do
			if filter_fn(self[index]) then
				self:remove(index)
				length = length - 1
			else
				index = index + 1
			end
		end
	end

end)

local stowage_backing = class(function (stowage_backing)
	function stowage_backing:init(db, db_key)
		self.db = db
		self.db_key = db_key
	end

	function stowage_backing:log_append(data)
		return self.db:log_append(self.db_key, data)
	end

	function stowage_backing:log_read(from_log_id, max_batch_size)
		return self.db:log_read(self.db_key, from_log_id, max_batch_size)
	end

	function stowage_backing:log_clear()
		return self.db:log_clear(self.db_key)
	end

	function stowage_backing:transaction(fn_operations)
		return self.db:transaction(fn_operations)
	end
end)


local silage = class(function (silage)

	function silage:init(stowagedb_or_backing, db_key)
		-- set up the backing, assume stowage backing must be constructed if we were supplied a db_key
		if db_key then
			rawset(self, 'backing', stowage_backing(stowagedb_or_backing, db_key))
		else
			rawset(self, 'backing', stowagedb_or_backing)
		end

		-- set up root objects and mappings (avoiding metatable)
		rawset(self, 'entities', setmetatable({}, {
			__mode = 'kv'
		}))
		rawset(self, 'root', silage_table(self, 1, 'map'))
		rawset(self, 'last_entity_id', 2)

		-- replay the log to create all entities and load in the required data
		local log_id = 0
		local batch_size = 256
		-- we need a non weakly referenced collection to use for the duration until inflation is complete
		local inflate_entities = {
			[1] = self.root
		}
		local function inflate(id, type)
			local entity = inflate_entities[id]
			if entity then
				if type and entity._type ~= type then
					error('type mismatch on reload [' .. db_key .. ']', 2)
				end
			else
				if type == nil then
					error('assign out of sequence [' .. db_key .. ']', 2)
				end
				entity = silage_table(self, id, type)
				inflate_entities[id] = entity
				if id > self.last_entity_id then
					self.last_entity_id = id
				end
			end
			return entity
		end

		-- replay the history log
		while true do
			local logs = self.backing:log_read(log_id, batch_size)
			for _, log in ipairs(logs) do
				-- inflate and assign the objects
				local event = log.data.event
				local id = log.data.id
				local key = log.data.key
				local value = log.data.value

				if event == 'map' then
					inflate(id, 'map')
				elseif event == 'array' then
					inflate(id, 'array')
				else
					-- inflate tables to entities
					if type(key) == 'table' then
						key = inflate(key.id)
					end
					if type(value) == 'table' then
						value = inflate(value.id)
					end
					if event == 'set' then
						inflate(id)._data[key] = value
					elseif event == 'insert' then
						table.insert(inflate(id, 'array')._data, key, value)
					elseif event == 'remove' then
						table.remove(inflate(id, 'array')._data, key)
					end
				end

			end
			if #logs < batch_size then
				break
			end
			log_id = logs[#logs].id
		end
	end

	-- create and wrap entities --------------------------------------------------------------

	function silage:create(...)
		return self.root:create(...)
	end

	function silage:map(...)
		return self.root:map(...)
	end

	function silage:array(...)
		return self.root:array(...)
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
						error('silage does allow mixing keys and values in different silages', 3)
					end
				else
					error('silage does not support tables with other metatables', 3)
				end
			else
				error('cannot set an unwrapped table', 3)
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
			if meta == nil or meta == array then
				-- create a new entity with this backing and a new entity id
				cycles_table = cycles_table or {}
				local next_entity_id = self.last_entity_id + 1;
				if value == create_as_empty_array or #value > 0 or meta == array then
					self:persist('array', next_entity_id)
					self.last_entity_id = next_entity_id
					local entity = silage_table(self, next_entity_id, 'array')
					cycles_table[value] = entity
					-- recursively wrap all entries
					for i, v in ipairs(value) do
						entity[i] = self:wrap(v, error_level + 1, cycles_table)
					end
					return entity
				else
					self:persist('map', next_entity_id)
					self.last_entity_id = next_entity_id
					local entity = silage_table(self, next_entity_id, 'map')
					cycles_table[value] = entity
					-- recursively wrap all the keys and values if we can
					for k, v in pairs(value) do
						if type(k) == 'number' and math.floor(k) == k and k >= 1 and k <= #value then
							-- ignore int value keys already traversed
						else
							entity[self:wrap(k, error_level + 1, cycles_table)] = self:wrap(v, error_level + 1, cycles_table)
						end
					end
					return entity
				end
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
		if type(value) == 'table' and getmetatable(value) == silage_table then
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
			for k, v in value:iterate() do
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
		self.backing:log_append(entry)
	end

	function silage:rewrite_log()
		self.backing:transaction(function ()
			-- create a fresh log
			self.backing:log_clear()
			-- temp mapping to prevent duplicaiton during rewrite
			local entities = {}
			local function write_entity(entity)
				if entities[entity._id] then
					return
				end
				entities[entity._id] = true
				if entity._type == 'array' then
					self:persist('array', entity._id)
				else
					self:persist('map', entity._id)
				end
				for k, v in entity:iterate() do
					if getmetatable(k) == silage_table then
						write_entity(k)
					end
					if getmetatable(v) == silage_table then
						write_entity(v)
					end
					self:persist('set', entity._id, k, v)
				end
			end
			write_entity(self.root)
		end)
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

-- set up some references to other classes if needed

-- allow access through the class to backing constructors
silage.silage_table = silage_table
silage.stowage_backing = stowage_backing

return silage