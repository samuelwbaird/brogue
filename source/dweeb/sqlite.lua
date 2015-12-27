-- wraps access to sqlite with
-- database
-- statement
-- result
-- query builder
-- copyright 2014 Samuel Baird MIT Licence

local table = require('table')
local string = require('string')

local sql = require('lsqlite3')

local class = require('core.class')
local array = require('core.array')
local cache = require('core.cache')

local result = class(function (result)

	function result:init(statement, sqlite_statement, sql_string)
		self.statement = statement
		self.sqlite_statement = sqlite_statement
		self.sql_string = sql_string
		-- pre-emptively step and see if its ok?
		self:step()
	end
	
	function result:step()
		-- print('step ' .. self.sql_string)
		local last_step = self.sqlite_statement:step()
		self.done = (last_step == sqlite3.DONE)
		self.has_row = (last_step == sqlite3.ROW)
		self.error = (not self.done and not self.has_row)
		if self.done then
			self.statement.done = true
			if self.statement.pool then
				self.statement.pool:release(self.statement)
			end
		end
		assert(not self.error, 'step: ' .. self.sql_string)
	end
	
	-- retrieve the value of the current row in different ways
	
	function result:value()
		if not self.has_row then
			return nil
		else
			return self.sqlite_statement:get_value(0)
			-- TODO: step the statement here to release it to the pool?
		end
	end
	
	function result:values()
		if not self.has_row then
			return nil
		else
			return self.sqlite_statement:get_uvalues()
		end
	end
	
	function result:array()
		if not self.has_row then
			return nil
		else
			return array(self.sqlite_statement:get_values())
		end
	end

	function result:row(metatable)
		if not self.has_row then
			return nil
		else
			return self.sqlite_statement:get_named_values()
		end
	end
	
	-- iterators
	
	function result:row_arrays()
		return function ()
			if self.done then
				return nil
			end
			local result = self:array()
			self:step()
			return result
		end
	end
	
	function result:row_values()
		return function ()
			if self.done then
				return nil
			end
			local result = self:values()
			self:step()
			return result
		end
	end
	
	function result:rows(metatable)
		if metatable then
			return function ()
				if self.done then
					return nil
				end
				local result = self:row()
				self:step()
				return setmetatable(result, metatable)
			end
		else
			return function ()
				if self.done then
					return nil
				end
				local result = self:row()
				self:step()
				return result
			end
		end
	end

	function result:with_each(row_function, metatable)
		for row in self:rows(metatable) do
			row_function(row)
		end
	end
end)

local statement = class(function (statement)
	
	function statement:init(sqlite_statement, sql_string, db)
		self.sqlite_statement = sqlite_statement
		self.sql_string = sql_string
		self.db = db
	end

	function statement:bind(bindings)
		self.sqlite_statement:reset()
		if bindings then
			assert(self.sqlite_statement:bind_names(bindings) == sqlite3.OK)
		end
	end
	
	function statement:dispose()
		self.sqlite_statement:finalize()
	end
	
	function statement:execute(bindings)
		self:bind(bindings)
		-- print('execute ' .. self.sql_string)
		assert(self.sqlite_statement:step() == sqlite3.DONE, 'error on execute ' .. self.sql_string .. ' ' .. (self.db.sqlite:error_message() or ''))
		self.done = true
		if self.pool then
			self.pool:release(self)
		end
		return true
	end
	
	function statement:query(bindings)
		self:bind(bindings)
		self.done = false
		return result(self, self.sqlite_statement, self.sql_string)
	end

end)

-- a pool for the same SQL query
local statement_pool = class(function (statement_pool)
	
	function statement_pool:init(db, sql_string)
		self.db = db
		self.sql_string = sql_string
		self.waiting = {}
	end
	
	function statement_pool:acquire(bindings)
		local statement = next(self.waiting)
		if statement then
			self.waiting[statement] = nil
			statement.done = false
			statement:bind(bindings)
			return statement
		end
		statement = self.db:prepare(self.sql_string, bindings)
		statement.pool = self
		return statement
	end
	
	function statement_pool:execute(bindings)
		return self:acquire():execute(bindings)
	end
	
	function statement_pool:query(bindings)
		return self:acquire():query(bindings)
	end
	
	function statement_pool:release(statement)
		self.waiting[statement] = statement
	end
	
end)

local builder = class(function (builder)
	
	function builder:init(db)
		self.db = db
		self.clauses = array()
		self.bindings = nil
	end
	
	-- get bindings and return field name and standins
	function builder:add_names_and_standins(new_bindings)
		if #new_bindings > 0 then
			local standins = array()
			for i = 1, #new_bindings do
				standins:push('?')
			end
			return new_bindings, standins
		else
			local field_names = array()
			local standins = array()
			if not self.bindings then
				self.bindings = array()
			end
			for k, v in pairs(new_bindings) do
				field_names:push(k)
				standins:push('?')
				self.bindings:push(v)
			end
			return field_names, standins
		end
	end
	
	function builder:where(where_fields, or_mode)
		local field_names, standins = self:add_names_and_standins(where_fields)
		local conditions = array()
		for _, field_name in ipairs(field_names) do
			-- does this include a >= style modifier
			if field_name:find('[^%w%s_]') then
				conditions:push(field_name .. ' ?')
			else
				conditions:push(field_name .. ' = ?')
			end
		end
		if or_mode then
			self.clauses:add('WHERE ' .. table.concat(conditions, ' OR '))
		else
			self.clauses:add('WHERE ' .. table.concat(conditions, ' AND '))
		end
		return self
	end
	
	function builder:where_or(where_fields)
		return self:where(where_fields, true)
	end
	
	function builder:limit(number)
		self.clauses:push('LIMIT ' .. number)
		return self
	end
	
	function builder:order_by(field1, ascdesc1, field2, ascdesc2, field3, ascdesc3, field4, ascdesc4)
		local order = array()
		if field1 then
			order:push(field1 .. ' ' .. (ascdesc1 or ''))
		end
		if field2 then
			order:push(field2 .. ' ' .. (ascdesc2 or ''))
		end
		if field3 then
			order:push(field3 .. ' ' .. (ascdesc3 or ''))
		end
		if field4 then
			order:push(field4 .. ' ' .. (ascdesc4 or ''))
		end
		self.clauses:push('ORDER BY ' .. table.concat(order, ', '))
		return self
	end
	
	function builder:select(table_name, select_fields, where_fields)
		select_fields = select_fields or '*'
		self.clauses:push('SELECT ' .. select_fields .. ' FROM ' .. table_name)
		if where_fields then
			self:where(where_fields)
		end
		return self
	end
	
	function builder:count(table_name, where_fields)
		select_fields = select_fields or '*'
		self.clauses:push('SELECT COUNT(*) FROM ' .. table_name)
		if where_fields then
			self:where(where_fields)
		end
		return self
	end
	
	function builder:update(table_name, set_fields, where_fields)
		self.clauses:push('UPDATE ' .. table_name .. ' SET ')
		local field_names, standins = self:add_names_and_standins(set_fields)
		local set_vars = array()
		for _, field_name in ipairs(field_names) do
			set_vars:push(field_name .. ' = ?')
		end
		self.clauses:push(table.concat(set_vars, ', '))
		if where_fields then
			self:where(where_fields)
		end
		return self
	end
	
	function builder:insert(table_name, fields)
		local field_names, standins = self:add_names_and_standins(fields)
		self.clauses:push('INSERT INTO ' .. table_name .. ' (' .. table.concat(field_names, ', ') .. ') VALUES (' .. table.concat(standins, ', ') .. ')')
		return self
	end
	
	function builder:upsert(table_name, fields)
		local field_names, standins = self:add_names_and_standins(fields)
		self.clauses:push('INSERT OR REPLACE INTO ' .. table_name .. ' (' .. table.concat(field_names, ', ') .. ') VALUES (' .. table.concat(standins, ', ') .. ')')
		return self
	end
	
	function builder:delete(table_name, where_fields)
		self.clauses:push('DELETE FROM ' .. table_name)
		if where_fields then
			self:where(where_fields)
		end
		return self
	end
	
	function builder:execute(bindings)
		if bindings and self.bindings then
			error('builder: names are bound cannot rebind this sql')
		end
		return self.db:execute(self:sql(), bindings or self.bindings)
	end
	
	function builder:query(bindings)
		if bindings and self.bindings then
			error('builder: names are bound cannot rebind this sql')
		end
		return self.db:query(self:sql(), bindings or self.bindings)
	end
	
	function builder:prepare()
		if self.bindings then
			error('builder: names are bound cannot prepare and rebind this sql ' .. self:sql())
		end
		return self.db:prepare(self:sql())
	end
	
	function builder:sql()
		return table.concat(self.clauses, ' ')
	end
	
	function builder:pool()
		return statement_pool(self.db, self:sql())
	end
	
end)

local db = class(function (db)
	
	function db:init(filename, exclusive)
		if filename then
			self.sqlite = sql.open(filename)
			if exclusive then
				self:pragma('locking_mode', 'EXCLUSIVE')
			end
		else
			self.sqlite = sql.open_memory()
		end
		self.query_cache = cache(1024)
		self.in_transaction = false
		self.pools = {}
		-- maintainance self:execute('VACUUM')
	end

	function db:close()
		self.sqlite:close()
	end
	
	-- primary access
	
	-- direct no pooling or bindings
	function db:exec(sql_string, bindings)
		assert(self.sqlite:exec(sql_string) == sqlite3.OK, 'error on exec ' .. sql_string .. ' ' .. (self.sqlite:error_message() or ''))
	end
	
	function db:pragma(name, value)
		return self:exec('PRAGMA ' .. name ..'=' .. value)
	end
	
	function db:execute(sql_string, bindings)
		local statement = self:pooled(sql_string, bindings)
		return statement:execute()
	end
	
	function db:query(sql_string, bindings)
		local statement = self:pooled(sql_string, bindings)
		return statement:query()
	end
	
	function db:pool(sql_string)
		return statement_pool(self, sql_string)
	end
	
	function db:pooled(sql_string, bindings)
		local pool = self.pools[sql_string]
		if not pool then
			pool = statement_pool(self, sql_string)
			self.pools[sql_string] = pool
		end
		return pool:acquire(bindings)
	end
	
	function db:prepare(sql_string, bindings)
		local sql_statement = statement(assert(self.sqlite:prepare(sql_string), 'prepare: ' .. sql_string), sql_string, self)
		if bindings then
			sql_statement:bind(bindings)
		end
		return sql_statement
	end
	
	function db:insert_id()
		return self.sqlite:last_insert_rowid()
	end
	
	-- transactions
	
	function db:begin_transaction()
		assert(not self.in_transaction, 'begin_transaction already in transaction state')
		self.in_transaction = true
		return self:execute('BEGIN TRANSACTION')
	end
	
	function db:abort_transaction()
		assert(self.in_transaction, 'abort not in transaction state')
		self.in_transaction = false
		return self:execute('ROLLBACK TRANSACTION')
	end
	
	function db:commit_transaction()
		assert(self.in_transaction, 'commit not in transaction state')
		self.in_transaction = false
		return self:execute('COMMIT TRANSACTION')
	end
	
	function db:transaction(transaction_code, ...)
		-- wrap a function in a transaction, abort on error
		if self.in_transaction then
			-- allow recursive transactions through
			transaction_code(...)
		else
			self:begin_transaction();
			local success, r1, r2, r3, r4, r5 = pcall(transaction_code, ...)
			if success then
				self:commit_transaction()
				return r1, r2, r3, r4, r5
			else
				self:abort_transaction()
				error(r1)
			end
		end
	end
	
	-- set up tables as required
	
	-- return all table names
	function db:tables()
		local out = array()
		local result = self:query('SELECT name FROM sqlite_master WHERE type="table" ORDER BY name')
		for table_name in result:row_values() do
			out:push(table_name)
		end
		return out
	end
	
	-- return a description of a given table
	function db:table(table_name)
		local result = self:query('SELECT * FROM sqlite_master WHERE tbl_name = ?', { table_name })
		if not result.has_row then
			return nil
		end

		local description = {
			columns = array(),
			indexes = array(),
		}
		
		local function add_column(column_sql)
			local name, type = column_sql:match('^%s*([^%s]+)%s*(.+)')
			description.columns:push({
				name = name,
				type = type
			})
		end
		local function add_index(index_sql)
			local name = index_sql:match('INDEX ([^%s]+)')
			name = name or ''
			local type = 'INDEX'
			if index_sql:find('UNIQUE') then
				type = 'UNIQUE'
			end
			local columns = array()
			local column_part = index_sql:match('%b()'):sub(2, -2)
			for column in column_part:gmatch('%s*([^,%s]+)%s*') do
				columns:push(column)
			end
			description.indexes:push({
				name = name,
				type = type,
				columns = columns
			})
		end
		
		for row in result:rows() do
			if row.type == 'table' then
				local column_part = row.sql:match('%b()'):sub(2, -2)
				for column in column_part:gmatch('([^,]+),?') do
					add_column(column)
				end
			elseif row.type == 'index' and row.sql then
				add_index(row.sql)
			end
		end
		
		-- for _, column in ipairs(description.columns) do
		-- 	print('column : ' .. column.name .. ' : ' .. column.type)
		-- end
		-- for _, index in ipairs(description.indexes) do
		-- 	print('index : ' .. index.name .. ' : ' .. index.type .. ' : ' .. table.concat(index.columns, ', '))
		-- end
		return description
	end
	
	-- alter a given table to make it match a given description
	function db:prepare_table(table_name, description)
		-- return true if the table changed in anyway
		local table_did_change = false
		
		-- prepare index names and standardise cache
		if description.indexes then
			for _, index in ipairs(description.indexes) do
				index.type = index.type:upper()
				if not index.name then
					index.name = table_name .. '_index_' .. table.concat(index.columns, '_')
				end
			end
		end

		local existing = self:table(table_name)
		if existing then
			-- reverse ref the existing stuff
			local existing_columns = {}
			for _, column in ipairs(existing.columns) do
				existing_columns[column.name] = column
			end
			local existing_indexes = {}
			for _, index in ipairs(existing.indexes) do
				existing_indexes[index.name] = index
			end
			-- add or update columns
			for _, column in ipairs(description.columns) do
				if existing_columns[column.name] then
					if existing_columns[column.name].type ~= column.type then
						error('sqlite: unable to update column ' .. table_name .. '.' .. column.name .. ' from ' .. existing_columns[column.name].type .. ' to ' .. column.type)
						table_did_change = true
					end
					existing_columns[column.name] = nil
				else
					table_did_change = true
					self:execute('ALTER TABLE ' .. table_name .. ' ADD COLUMN ' .. column.name .. ' ' .. column.type)
				end
			end
			-- add or update indexes
			for _, index in ipairs(description.indexes) do
				if existing_indexes[index.name] then
					if index.type ~= existing_indexes[index.name].type or table.concat(index.columns, ', ') ~= table.concat(existing_indexes[index.name].columns, ', ') then
						table_did_change = true
						self:execute('DROP INDEX ' .. index.name)
						self:execute('CREATE ' .. index.type .. ' ' .. index.name .. ' ON ' .. table_name .. '(' .. table.concat(index.columns, ', ') .. ')')
					end
					existing_indexes[index.name] = nil
				else
					table_did_change = true
					self:execute('CREATE ' .. index.type .. ' ' .. index.name .. ' ON ' .. table_name .. '(' .. table.concat(index.columns, ', ') .. ')')
				end
			end
			-- remove unneeded columns
			for name, index in pairs(existing_indexes) do
				table_did_change = true
				self:execute('DROP INDEX ' .. name)
			end
			for name, type in pairs(existing_columns) do
				table_did_change = true
				error('sqlite: unable to remove column ' .. table_name .. '.' .. name)
			end
		else
			-- create table if not already present
			table_did_change = true
			local table_description_clause = array()
			local table_add_indexes = array()
			if description.columns then
				for _, column in ipairs(description.columns) do
					table_description_clause:push(column.name .. ' ' .. column.type)
				end
				self:execute('CREATE TABLE ' .. table_name .. ' (' .. table.concat(table_description_clause, ', ') .. ')')
			end
			if description.indexes then
				for _, index in ipairs(description.indexes) do
					self:execute('CREATE ' .. index.type .. ' ' .. index.name .. ' ON ' .. table_name .. '(' .. table.concat(index.columns, ', ') .. ')')
				end
			end
		end
		
		return table_did_change
	end
	
	-- short cut builder to common queries
	
	function db:select(...)
		local builder = builder(self)
		return builder:select(...)
	end
	
	function db:count(...)
		local builder = builder(self)
		return builder:count(...)
	end
	
	function db:insert(...)
		local builder = builder(self)
		return builder:insert(...)
	end
	
	function db:upsert(...)
		local builder = builder(self)
		return builder:upsert(...)
	end
	
	function db:update(...)
		local builder = builder(self)
		return builder:update(...)
	end
	
	function db:delete(...)
		local builder = builder(self)
		return builder:delete(...)
	end
	
end)

return db