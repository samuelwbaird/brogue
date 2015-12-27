-- top level object defining an ORM model
-- registers classes and controls transactions
-- ORM based objects can only be updated within a transaction
-- copyright 2014 Samuel Baird MIT Licence

local class = require('core.class')
local array = require('core.array')
local cache = require('core.cache')

-- external modules
local cmsgpack = require('cmsgpack')
local sqlite = require('dweeb.sqlite')

local model_class = require('dweeb.model_class')

return class(function (model)
	
	function model:init(db_name)
		self.db = assert(sqlite(db_name, true))
		self.classes = {}
		self.in_transaction = false
	end
	
	-- top level manage the data
	
	function model:close()
		self.db:close()
	end
	
	function model:begin_transaction()
		assert(not self.db.in_transaction, 'model: already in transaction')
		self.dirty_set = {}
		self.in_transaction = true
		self.db:begin_transaction()
	end
	
	function model:commit_transaction()
		assert(self.in_transaction, 'model: not in transaction')
		-- push all updates to non-indexed data from the dirty set
		for instance in pairs(self.dirty_set) do
			instance:commit_transaction()
		end
		self.db:commit_transaction()
		self.in_transaction = false
		self.dirty_set = nil
	end
	
	function model:abort_transaction()
		assert(self.in_transaction, 'model: not in transaction')
		for instance in pairs(self.dirty_set) do
			instance:abort_transaction()
		end
		self.db:abort_transaction()
		self.in_transaction = false
		self.dirty_set = nil
	end
	
	function model:transaction(transaction_code, ...)
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
	
	function model:update_instance_in_transaction(instance)
		assert(self.in_transaction, 'model: update not in transaction')
		self.dirty_set[instance] = instance
		return true
	end
	
	-- define the model
	
	function model:class(class_name)
		return self.classes[class_name]
	end
	
	function model:define_class(class_name, indexed_fields, additional_indexes, cache_size)
		local new_class = model_class(self, class_name, indexed_fields, additional_indexes, cache_size)
		self.classes[class_name] = new_class
		self[class_name] = new_class
		return new_class
	end

end)