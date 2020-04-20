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
		
		self.in_transaction = false
		self.transaction_is_dirty = false
	end	
	
	function stowage:close()
		self.db:close()
	end
	
	-- create a new key, return true if successful (ie. the key does not already exist)
	function stowage:create(key, initial_value, reverse_values)
		if self.in_transaction then
			self.transaction_is_dirty = true
		end
		
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
		if self.in_transaction then
			self.transaction_is_dirty = true
		end
		
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
		if self.in_transaction then
			self.transaction_is_dirty = true
		end
		
		self.db:transaction(function (db, statements)
			statements.upsert_value:execute({ key, cmsgpack.pack(value) })
			
			if reverse_values then
				statements.delete_reverse_key:execute({ key })
				for _, value in ipairs(reverse_values) do
					statements.insert_reverse:execute({ value, key })
				end
			end
		end, self.db, self.statements)
	end

	-- sequential log per key ---------------------------------------------------------
	
	function stowage:log_append(key, data)
		assert(key, 'cannot log to nil key')
		
		if self.in_transaction then
			self.transaction_is_dirty = true
		end
		
		self.statements.insert_log:execute({ key, cmsgpack.pack(data) })
	end
	
	function stowage:log_read(key, after_log_id, max)
		local output = array()
		local rows = nil
		if max then
			rows = self.statements.read_log_with_limit:query({ key, after_log_id, max }):rows()
		elseif after_log_id then
			rows = self.statements.read_log_from_id:query({ key, after_log_id }):rows()
		else
			rows = self.statements.read_log:query({ key }):rows()
		end
		for row in rows do
			output:push({
				id = row.id,
				data = cmsgpack.unpack(row.data),
			})
		end
		return output
	end
	
	function stowage:log_read_reverse(key, count)
		local output = array()
		local rows = self.statements.read_log_reverse_with_limit:query({ key, count }):rows()
		for row in rows do
			output:push({
				id = row.id,
				data = cmsgpack.unpack(row.data),
			})
		end
		return output
	end
	
	function stowage:log_clear(key, up_to_log_id)
		if self.in_transaction then
			self.transaction_is_dirty = true
		end
		
		if up_to_log_id then
			self.statements.delete_log_up_to_id:execute({ key, up_to_log_id })
		else
			self.statements.delete_log:execute({ key })
		end
	end
	
	function stowage:log_remove(key, log_id)
		if self.in_transaction then
			self.transaction_is_dirty = true
		end
		
		self.statements.delete_log_id:execute({ key, log_id })
	end
	
	-- reverse index ------------------------------------------------------------------
	
	-- set one or many reverse index values pointing to a key
	function stowage:reverse_set(key, reverse_values)
		if self.in_transaction then
			self.transaction_is_dirty = true
		end
		
		self.db:transaction(function (db, statements)
			statements.delete_reverse_key:execute({ key })
			for _, value in ipairs(reverse_values) do
				statements.insert_reverse:execute({ value, key })
			end
		end, self.db, self.statements)
	end
	
	-- remove all reverse references to this key
	function stowage:reverse_remove(key)
		if self.in_transaction then
			self.transaction_is_dirty = true
		end
		
		self.statements.delete_reverse_key:execute({ key })
	end
	
	-- retrieve all they keys that are reverse referenced by this value
	function stowage:reverse_query(value)
		local keys = array()
		for row in self.statements.get_reverse_keys:query({ value }):rows() do
			keys:push(row.key)
		end
		return keys
	end
	
	-- retrieve the first key that matches this reverse reference
	function stowage:reverse_query_one(value)
		return self.statements.get_reverse_key:query({ value }):value()
	end
	
	-- retrieve the first reverse value with this prefix
	function stowage:reverse_first(prefix)
		local value = self.statements.get_reverse_from:query({ value }):value()
		if value and value:sub(1, #prefix) ~= prefix then
			return nil
		end
		return value
	end
	
	-- bulk keys --------------------------------------------------------------------
	
	-- return all keys for a given key prefiex
	function stowage:get_keys(prefix)
		local keys = array()
		local query_result = self.statements.get_keys_from:query({ prefix })
		for row in query_result:rows() do
			if row.key:sub(1, #prefix) == prefix then
				keys:push(row.key)
			else
				query_result:release()
				break
			end
		end
		return keys
	end
	
	-- remove all keys for a given key prefix
	function stowage:remove_keys(prefix)
		if self.in_transaction then
			self.transaction_is_dirty = true
		end
		
		local query_result = self.statements.get_keys_from:query({ prefix })
		for row in query_result:rows() do
			if row.key:sub(1, #prefix) == prefix then
				self:remove(key)
			else
				query_result:release()
				break
			end
		end
	end
	
	-- return the next key that matches or follows a given prefix
	function stowage:next_key(prefix, must_match_prefix)
		local key = self.statements.get_key_from:query({ prefix }):value()
		if must_match_prefix and key and key:sub(1, #prefix) ~= prefix then
			return nil
		end
		return key
	end
	
	-- return the next key after a given key
	function stowage:key_after_key(key)
		return self.statements.get_key_after:query({ key }):value()
	end

	-- enumerate keys in bulk
	function stowage:keys_after_key(key, limit)
		local output = array()
		local query_result = self.statements.get_keys_after:query({ key, limit })
		for row in query_result:rows() do
			output:push(row.key)
		end
		return output
	end
	
	-- return a lua iterate that iterates over a prefix, transparently batching if required
	function stowage:iterate_keys(prefix)
		local key = prefix
		
		return function ()
			key = self:key_after_key(key)
			-- end of db
			if not key then
				return nil
			end
			-- prefix no longer matches
			if key:sub(1, #prefix) ~= prefix then
				return nil
			end
			-- otherwise its the next value
			return key
		end
	end
	
	-- proxy sqlite transaction support through to this level as its critical to batch commits in practice

	function stowage:begin_transaction()
		if self.in_transaction then
			error('stowage already in transaction state', 2)
		end
		self.in_transaction = true
		self.transaction_is_dirty = false
		return self.db:begin_transaction()
	end
	
	function stowage:abort_transaction()
		self.in_transaction = false
		self.transaction_is_dirty = false
		return self.db:abort_transaction()
	end
	
	function stowage:commit_transaction()
		self.in_transaction = false
		self.transaction_is_dirty = false
		return self.db:commit_transaction()
	end

	function stowage:transaction(...)
		return self.db:transaction(...)
	end
	
	-- internal, prepare all sqlite statements required -----------------------------
	
	function stowage:prepare_db(db)
		-- main key value table
		db:prepare_table('keys', {
			columns = {
				{ name = 'key', type = 'TEXT UNIQUE' },
				{ name = 'value', type = 'TEXT' },		-- msgpack encoded
			},
			indexes = {},
		})
		
		-- append mutable events to a log per key
		db:prepare_table('log', {
			columns = {
				{ name = 'id', type = 'INTEGER PRIMARY KEY AUTOINCREMENT' },
				{ name = 'key', type = 'TEXT' },
				{ name = 'data', type = 'TEXT' },		-- msgpack encoded
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
		statements.insert_log = db:insert('log', { 'key', 'data' }):prepare()
		statements.read_log = db:select('log', 'id, data', { 'key' }):order_by('id', 'asc'):prepare()
		statements.read_log_from_id = db:select('log', 'id, data', { 'key', 'id >' }):order_by('id', 'asc'):prepare()
		statements.read_log_with_limit = db:prepare('select id, data from `log` where `key` = ? and `id` > ? order by `id` asc limit ?')
		statements.read_log_reverse_with_limit = db:prepare('select id, data from `log` where `key` = ? order by `id` desc limit ?')
		statements.delete_log = db:delete('log', { 'key' }):prepare()
		statements.delete_log_up_to_id = db:delete('log', { 'key', 'id <='}):prepare()
		statements.delete_log_id = db:delete('log', { 'key', 'id' }):prepare()
		
		-- reverse index table statements
		statements.delete_reverse_key = db:delete('reverse', { 'key' }):prepare()
		statements.insert_reverse = db:insert('reverse', { 'value', 'key' }):prepare()
		statements.get_reverse_keys = db:select('reverse', 'key', { 'value' }):prepare()
		statements.get_reverse_key = db:select('reverse', 'key', { 'value' }):limit(1):prepare()
		statements.get_reverse_from = db:select('reverse', 'value', { 'value >=' }):limit(1):prepare()
		
		-- export keys
		statements.get_key_from = db:select('keys', 'key', { 'key >=' }):limit(1):prepare()
		statements.get_keys_from = db:select('keys', 'key', { 'key >=' }):prepare()

		statements.get_key_after = db:select('keys', 'key', { 'key >' }):limit(1):prepare()
		statements.get_keys_after = db:prepare('select key from `keys` where `key` > ? order by `key` limit ?')
		
		return statements
	end
	
end)