-- this module is used to generate an instance factory for each class in the model
-- instances will record updates to index and arbitrary fields
-- updates to indexed fields are written to the database immediately for use in
-- queries, updates to arbitrary fields are written on commit
-- all updates are only allowed within transactions and can be rolled back
-- instances with the same id will always reuse the same Lua object
-- copyright 2014 Samuel Baird MIT Licence

local module = require('core.module')
local class = require('core.class')
local array = require('core.array')
local cache = require('core.cache')

-- external modules
local cmsgpack = require('cmsgpack')
local sqlite = require('dweeb.sqlite')

return module(function (model_instance_factory)
	
	-- generate a new instance factory for each class in the model
	function model_instance_factory.prepare(class_name, model_class, model, db)

		local function clone(existing_table)
			local new_table = {}
			for k, v in pairs(existing_table or {}) do
				new_table[k] = v
			end
			return new_table
		end
	
		local function deflate_value(value)
			if type(value) == 'table' then
				if value.class and value.id then
					return {
						class = value.class.class_name,
						id = value.id
					}
				else
					local table = {}
					for k, v in pairs(value) do
						table[k] = deflate_value(v)
					end
					return table
				end
			else
				return value
			end
		end
	
		local function inflate_value(value)
			if type(value) == 'table' then
				if value.class and value.id then
					return model:class(value.class)(value.id)
				else
					local table = {}
					for k, v in pairs(value) do
						table[k] = inflate_value(v)
					end
					return table
				end
			else
				return value
			end
		end
		
		-- prepared sql
		local sql_set_data_pool = db:update(class_name, { 'data' }, { 'id' }):pool()
		local properties = {}

		return class(function (instance)
			local super = instance.new
			
			instance.model_class = model_class

			function instance.new(id, indexed_field_values, data_values)
				local self = super()

				rawset(self, 'id', id)
				rawset(self, 'indexed_fields', clone(indexed_field_values))
				rawset(self, 'data', clone(data_values))

				return self
			end

			function instance:flatten()
				local out = {}
				for key, value in pairs(rawget(self, 'data')) do
					out[key] = value
				end
				for key, value in pairs(rawget(self, 'indexed_fields')) do
					out[key] = value
				end
				out.id = self.id
				return out
			end


			function instance.register_property(name, get, set)
				properties[name] = {
					get = get,
					set = set,
				}
			end

			function instance.register_constant(name, value)
				instance.register_property(name, function ()
					return value
				end)
			end

			function instance.register_index(name)
				local prepared_set_index = db:prepare('UPDATE `' .. class_name .. '` SET `' .. name .. '` = ? WHERE `id` = ?')
				
				instance.register_property(name,
					function (instance, key, indexed_fields)
						return rawget(instance, 'indexed_fields')[key]
					end,
					function (instance, key, value, indexed_fields)
						rawget(instance, 'indexed_fields')[key] = value
						-- update the database immediately
						prepared_set_index:execute({ value, instance.id })
					end)
			end

			function instance:__newindex(key, new_value)
				-- must be in transaction state
				self:dirty()
				
				-- check the class
				local value = instance[key]
				assert(not value, 'cannot overwrite instance method ' .. key)

				-- check the properties
				local value = properties[key]
				if value then
					assert(value.set, 'cannot set instance property ' .. key)
					return value.set(self, key, new_value, rawget(self, 'indexed_fields'), rawget(self, 'data'))
				end	

				-- otherwise update adhoc values
				-- transparently & recursively deflate instances to class+id
				rawget(self, 'data')[key] = deflate_value(new_value)
			end

			function instance:__index(key)
				-- check the class
				local value = instance[key]
				if value then
					return value
				end	

				-- check the properties
				local value = properties[key]
				if value then
					assert(value.get, 'cannot get instance property ' .. key)
					return value.get(self, key, rawget(self, 'indexed_fields'), rawget(self, 'data'))
				end	

				-- then check the adhoc data
				local value = self.data[key]
				-- transparently & recursively inflate class+id into instances
				if value then return inflate_value(value) end

				return nil
			end

			function instance:dirty()
				if not rawget(self, 'rollback_indexes') then
					model:update_instance_in_transaction(self)
					rawset(self, 'rollback_indexes', clone(self.indexed_fields))
					rawset(self, 'rollback_data', clone(self.data))
				end
			end

			function instance:abort_transaction()
				assert(rawget(self, 'rollback_indexes'), 'abort instance changes with no changes')
				rawset(self, 'indexed_fields', rawget(self, 'rollback_indexes'))
				rawset(self, 'data', rawget(self, 'rollback_data'))
				rawset(self, 'rollback_indexes', nil)
				rawset(self, 'rollback_data', nil)
			end

			function instance:commit_transaction()
				assert(rawget(self, 'rollback_indexes'), 'commit instance changes with no changes')
				-- commit additional fields to the database
				sql_set_data_pool:acquire({ cmsgpack.pack(self.data), self.id }):execute()

				-- clear rollback/dirty state
				rawset(self, 'rollback_indexes', nil)
				rawset(self, 'rollback_data', nil)
			end

		end)
		
		
	end
	
end)
