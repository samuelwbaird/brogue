-- provides a sort of key value store (with sqlite backing)
-- with very fixed semantics, each database key has:
--
-- an atomic value
-- a log, of immutable objects, the log is sequential and can be cleared
-- a reverse index, where any number of values can be linked to a key
--
-- export methods, not necessarily suitable for direct network access
-- provide methods to traverse multiple keys
--
-- all method are isolated atomic transactions
--
-- copyright 2019 Samuel Baird MIT Licence

local class = require('core.class')
local array = require('core.array')

local sqlite = require('dweeb.sqlite')
local cmsgpack = require('cmsgpack')

return class(function (stowage)
	math.randomseed(os.time())
	
	function stowage:init(db_name, exclusive)
		local db = assert(sqlite(db_name, true), 'cannot create stowage sqlite file ' .. (db_name or '<nil>'))
		
		self.db = self:prepare_db(db)
		self.statements = self:prepare_db_statements(db)
		
		self.random_suffix_chars = '1234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'	
		self.random_suffix_length = 8
	end	
		
	-- create a new key, return true if successful (ie. the key does not already exist)
	function stowage:create(key, initial_value, reverse_values)
		return self.db:transaction(function (db, statements)
			if statements.has_key:query({ key }).has_row then
				return false
			end
			
			statements.insert_value:execute({ key, cmsgpack.pack(initial_value) })
			
			if reverse_values then
				for _, value in ipairs(reverse_values) do
					statements.insert_reverse:execute({ value, key })
				end
			end
			
			return true
		end, self.db, self.statements)
	end
	
	-- create a new key, using a fixed prefix and a random unique suffiz
	-- return the new key
	function stowage:create_new(prefix, initial_value, reverse_values)
		local random_chars = self.random_suffix_chars
		local length = self.random_suffix_length
		while true do
			local key = { prefix }
			for i = 1, length do
				local index = math.random(1, #random_chars)
				key[#key + 1] = random_chars:sub(index, index)
			end
			key = table.concat(key)
			if self:create(key, initial_value, reverse_values) then
				return key
			end
			length = length + 1
		end
	end

	-- completely remove a key and all its related values
	function stowage:remove(key)
		self.db:transaction(function (db, statements)
			statements.delete_value:execute({ key })
			statements.delete_log:execute({ key })
			statements.delete_reverse_key:execute({ key })
		end, self.db, self.statements)
	end

	-- atomic value per key ------------------------------------------------------------

	-- return the atomic value for this key
	function stowage:get_value(key)
		local value = self.statements.get_value:query({ key }):value()
		return value and cmsgpack.unpack(value)
	end
	
	-- set the atomic value for this key (and optionally reset the reverse index)
	function stowage:set_value(key, value, reverse_values)
		self.db:transaction(function (db, statements)
			statements.upsert_value:execute({ key, value })
			
			if reverse_values then
				statements.delete_reverse_key:execute({ key })
				for _, value in ipairs(reverse_values) do
					statements.insert_reverse:execute({ value, key })
				end
			end
		end, self.db, self.statements)
	end

	-- sequential log per key ---------------------------------------------------------
	
	function stowage:log_append(key, event)
		self.statements.insert_log:execute({ key, cmsgpack.pack(event) })
	end
	
	function stowage:log_read(key, max, after_log_id)
		local output = array()
		
		return output
	end
	
	function stowage:log_clear(key, up_to_log_id)
		if up_to_log_id then
			self.statements.delete_log_up_to_id:execute({ key, up_to_log_id })
		else
			self.statements.delete_log:execute({ key })
		end
	end
	
	function stowage:log_remove(key, log_id)
		self.statements.delete_log_id:execute({ key, log_id })
	end
	
	-- reverse index ------------------------------------------------------------------
	
	-- set one or many reverse index values pointing to a key
	function stowage:reverse_set(key, reverse_values)
		self.db:transaction(function (db, statements)
			statements.delete_reverse_key:execute({ key })
			for _, value in ipairs(reverse_values) do
				statements.insert_reverse:execute({ value, key })
			end
		end, self.db, self.statements)
	end
	
	-- remove all reverse references to this key
	function stowage:reverse_remove(key)
		self.statements.delete_reverse_key:execute({ key })
	end
	
	-- retrieve all they keys that are reverse referenced by this value
	function stowage:reverse_query(value)
	end
	
	-- retrieve the first reverse value with this prefix
	function stowage:reverse_first(prefix)
	end
	
	-- export keys --------------------------------------------------------------------
	
	-- return all keys for a given key prefiex
	function stowage:export_keys(prefix)
	end
	
	-- export all aspects of a key as a single value
	function stowage:export(key)
	end
	
	-- export all aspects of all keys for a prefix as an array of values
	function stowage:export_prefix(prefix)
	end
	
	-- remove all keys for a given key prefix
	function stowage:remove_prefix(prefix)
	end
	
	-- internal, prepare all sqlite statements required -----------------------------
	
	function stowage:prepare_db(db)
		-- main key value table
		db:prepare_table('keys', {
			columns = {
				{ name = 'key', type = 'TEXT UNIQUE' },
				{ name = 'value', type = 'TEXT' },
			},
			indexes = {},
		})
		
		-- append mutable events to a log per key
		db:prepare_table('log', {
			columns = {
				{ name = 'id', type = 'INTEGER PRIMARY KEY AUTOINCREMENT' },
				{ name = 'key', type = 'TEXT' },
				{ name = 'value', type = 'TEXT' },
			},
			indexes = {
				{ columns = { 'key', 'id' }, type = 'INDEX' },
			},
		})
		
		-- reverse index from values to keys
		db:prepare_table('reverse', {
			columns = {
				{ name = 'value', type = 'TEXT' },
				{ name = 'key', type = 'TEXT' },
			},
			indexes = {
				{ columns = { 'value', 'key' }, type = 'INDEX' },
				{ columns = { 'key' }, type = 'INDEX' },
			},
		})
		
		return db
	end
	
	function stowage:prepare_db_statements(db)
		local statements = {}
		
		-- main key value table statements
		statements.has_key = db:select('keys', 'key', { 'key' }):prepare()
		statements.get_value = db:select('keys', 'value', { 'key' }):prepare()
		statements.insert_value = db:insert('keys', { 'key', 'value' }):prepare()
		statements.delete_value = db:delete('keys', { 'key' }):prepare()
		statements.upsert_value = db:upsert('keys', { 'key', 'value' }):prepare()
		
		-- log table statements
		statements.insert_log = db:insert('log', { 'key', 'value' }):prepare()
		statements.delete_log = db:delete('log', { 'key' }):prepare()
		statements.delete_log_up_to_id = db:delete('log', { 'key', 'id <='}):prepare()
		statements.delete_log_id = db:delete('log', { 'key', 'id' }):prepare()
		
		-- reverse index table statements
		statements.delete_reverse_key = db:delete('reverse', { 'key' }):prepare()
		statements.insert_reverse = db:insert('reverse', { 'value', 'key' }):prepare()
		
		return statements
	end
	
end)