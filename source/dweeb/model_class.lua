-- model_class objects define each class in the ORM model
-- once a model_class object has been created through model:define_class it can be
-- used to add relationships to that class and to query and retrieve instances
-- copyright 2014 Samuel Baird MIT Licence

local module = require('core.module')
local class = require('core.class')
local array = require('core.array')
local cache = require('core.cache')

-- external modules
local cmsgpack = require('cmsgpack')

-- local module
local sqlite = require('dweeb.sqlite')
local view = require('dweeb.view')
local model_instance_factory = require('dweeb.model_instance_factory')

return class(function (model_class)
	
	function model_class:init(model, class_name, indexed_fields, additional_indexes, cache_size, on_inflate)
		self.model = model
		self.db = model.db
		self.class_name = class_name
		self.indexed_fields = indexed_fields
		self.cache = cache(cache_size)
		self.on_inflate = on_inflate
		
		-- prepare the DB
		local columns = array({
			{ name = 'id', type = 'INTEGER PRIMARY KEY AUTOINCREMENT' },
		})
		local indexes = array()
		if indexed_fields then
			for k, v in pairs(indexed_fields) do
				columns:push({ name = k, type = v })
				if not v:find(' UNIQUE') then
					indexes:push({ columns = { k }, type = 'INDEX' })
				end
			end
		end
		-- handle any adhoc fields
		columns:push({ name = 'data', type = 'TEXT' })
		self.db:prepare_table(class_name, {
			columns = columns,
			indexes = indexes,
		})
		
		-- prepared statement
		self.db_get_by_id = self.db:prepare('SELECT * FROM `' .. class_name .. '` WHERE id = ?')
		
		-- find the highest id in the database
		self.last_id = self.db:query('SELECT id from `' .. class_name .. '` ORDER BY `id` DESC LIMIT 1'):value() or 0
		self.next_id = self.last_id + 1

		-- prepare a specific metatable/factory for these instances
		self.class_instance_factory = model_instance_factory.prepare(class_name, self, model, self.db)
		self.class_instance_factory.register_constant('model', model)
		self.class_instance_factory.register_constant('class', self)
		self.class_instance_factory.register_constant('class_name', class_name)
		if indexed_fields then
			for k, v in pairs(indexed_fields) do
				self.class_instance_factory.register_index(k)
			end
		end
	end
	
	function model_class:is_field_indexed(field_name)
		return self.indexed_fields[field_name] ~= nil
	end
	
	function model_class:inflate(id, latest_db_values)
		-- check the cache, always use the cached instance if available
		-- main purpose of the cache is for coherence, not speed, one id = one object
		local instance = self.cache:get(id)
		if instance then
			return instance
		end
		assert(latest_db_values, self.class_name .. ' inflate, no values')
		-- separate packed data to additional fields here
		local data = cmsgpack.unpack(latest_db_values.data) or {}
		latest_db_values.data = nil
		instance = self.class_instance_factory(id, latest_db_values, data)
		self.cache:push(id, instance)
		if self.on_inflate then
			self.on_inflate(instance, self.model)
		end
		return instance
	end
	
	function model_class:create(initial_values)
		assert(self.model.in_transaction, 'create instance outside transaction')
		
		self.last_id = self.next_id
		self.next_id = self.last_id + 1
		
		local id = self.last_id
		initial_values = initial_values or {}
		-- insert the new instance in the database, at least the id and indexed fields
		local insert_values = {
			id = id
		}
		local data = {}
		for key, value in pairs(initial_values) do
			if self.indexed_fields[key] then
				insert_values[key] = value
			else
				data[key] = value
			end
		end
		self.db:insert(self.class_name, insert_values):execute()
		-- now prep the in memory instance
		local instance = self.class_instance_factory(id, insert_values, nil)
		-- set by key, value to trigger properties
		for k, v in pairs(data) do
			instance[k] = v
		end
		instance:dirty()
		self.cache:push(id, instance)
		if self.on_inflate then
			self.on_inflate(instance, self.model)
		end
		return instance
	end
	
	
	function model_class:__call(id)
		id = tonumber(id)
		if not id then
			return nil
		end
		-- assert(id, 'must include numeric instance id')
		local instance = self.cache:get(id)
		if instance then
			return instance
		end
		local values = self.db_get_by_id:query({ id }):row()
		if values then
			return self:inflate(id, values)
		else
			return nil
		end
	end
	
	function model_class:get(query)
		assert(type(query) == 'table', 'instance get must contain where clause')
		local values = self.db:select(self.class_name, '*', query):query():row()
		if values then
			return self:inflate(values.id, values)
		else
			return nil
		end
	end
	
	function model_class:iterate(where_fields)
		-- either all or filtered, return an iterator (could optimise a pool for the nil where_fields case)
		local db_iter = self.db:select(self.class_name, '*', where_fields):query():rows()
		local done = false
		return function ()
			if done then
				return nil
			end
			local row = db_iter()
			if not row then
				done = true
				return nil
			end
			return self:inflate(row.id, row)
		end
	end
	
	function model_class:collect(where_fields)
		-- either all or filtered, return as an array
		return array():collect(self:iterate(where_fields))
	end
	
	function model_class:define_relationship(name, other_class, id_field)
		id_field = id_field or name
		
		if self:is_field_indexed(id_field) then
			local prepared_set_index = self.db:prepare('UPDATE `' .. self.class_name .. '` SET `' .. id_field .. '` = ? WHERE `id` = ?')
			
			self.class_instance_factory.register_property(name,
				function (instance, key, indexed_fields, additional_fields)
					local id = rawget(instance, 'indexed_fields')[id_field]
					if tonumber(id) then
						return other_class(id)
					else
						return nil
					end
				end,

				function (instance, key, value, indexed_fields, additional_fields)
					rawget(instance, 'indexed_fields')[id_field] = value and value.id or 0
					-- update the database immediately
					prepared_set_index:execute({ value and value.id or 0, instance.id })
				end)
				
		else
			self.class_instance_factory.register_property(name,
				function (instance, key, indexed_fields, additional_fields)
					local id = rawget(instance, 'data')[id_field]
					if tonumber(id) then
						return other_class(id)
					else
						return nil
					end
				end,

				function (instance, key, value, indexed_fields, additional_fields)
					rawget(instance, 'data')[id_field] = value.id
				end)
		end
	end
	
	function model_class:define_collection(name, other_class, reverse_id)
		local pool = self.db:select(other_class.class_name, '*', { reverse_id }):pool()

		-- a function that returns an iterator, or if called with true returns the complete array
		local outer = function (instance, all_at_once)
			local result = pool:acquire({ instance.id }):query()
			if all_at_once then
				local output = array()
				for row in result:rows() do
					output:push(other_class:inflate(row.id, row))
				end
				return output
			else
				return function ()
					if not result or result.done then
						result = nil
						return nil
					end
					local row = result:row()
					result:step()
					return other_class:inflate(row.id, row)
				end
			end
		end

		-- add new behaviour to the metatable
		self.class_instance_factory.register_property(name, function (instance)
			return outer
		end)
	end
	
	function model_class:define_property(name, getter, setter)
		self.class_instance_factory.register_property(name, getter, setter)
	end
	
	function model_class:define_method(name, fn)
		self.class_instance_factory.register_constant(name, fn)
	end
	
	function model_class:define_static_method(name, fn, proxy_self)
		if proxy_self then
			self[name] = function (model_class, ...)
				return fn(proxy_self or model_class, ...)
			end
		else
			self[name] = fn
		end
	end
	
	function model_class:define_view(name, definition, ...)
		local v = view(definition, ...)
		self.class_instance_factory.register_property(name, function (instance)
			return function ()
				return v:externalise(instance)
			end
		end)
		return v
	end

end)