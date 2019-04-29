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

return class(function (stowage)
	
	function stowage:init(db_name, exclusive)
		local db = assert(sqlite(db_name, true), 'cannot create stowage sqlite file ' .. (db_name or '<nil>'))
		
		self.db = self:prepare_db(db)
		self.statements = self:prepare_db_statements(db)
	end	
		
	-- create a new key, return true if successful (ie. the key does not already exist)
	function stowage:create(key, initial_value, reverse_values)
		return self.db:transaction(function (db, statements)
			if statements.has_key:query({ key }).has_row then
				return false
			end
			
			return true
		end, self.db, self.statements)
	end
	
	-- create a new key, using a fixed prefix and a random unique suffiz
	-- return the new key
	function stowage:create_new(prefix, initial_value, reverse_values)
	end

	-- completely remove a key and all its related values
	function stowage:remove(key)
	end

	-- atomic value per key ------------------------------------------------------------

	-- return the atomic value for this key
	function stowage:get_value(key)
	end
	
	-- set the atomic value for this key (and optionally reset the reverse index)
	function stowage:set_value(key, value, reverse_values)
	end

	-- sequential log per key ---------------------------------------------------------
	
	function stowage:log_append(key, event)
	end
	
	function stowage:log_read(key, max, after_log_id)
	end
	
	function stowage:log_clear(key, up_to_log_id)
	end
	
	function stowage:log_remove(key, log_id)
	end
	
	-- reverse index ------------------------------------------------------------------
	
	-- set one or many reverse index values pointing to a key
	function stowage:reverse_set(key, values)
	end
	
	-- remove all reverse references to this key
	function stowage:reverse_remove(key)
	end
	
	-- retrieve all they keys that are reverse referenced by this value
	function stowage:reverse_query(value)
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
		
		-- log table statements
		-- insert
		
		-- reverse index table statements
		
		
		
		
		
		
		-- -- prepare statements to use for all transactions
		-- local select_statement = db:select('codes', 'id, code' , { 'code' }):prepare()
		-- local delete_statement = db:delete('codes', { 'id' }):prepare()
		-- delete_statement:execute({ 12 })
		-- delete_statement:execute({ 13 })
		-- delete_statement:execute({ 14 })
		
		
		
		return statements
	end
	
end)