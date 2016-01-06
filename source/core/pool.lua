-- manage a pool of active and inactive objects
-- supply a constructor or metatable to populate new objects
-- maintain references to active and inactive objects
-- copyright 2016 Samuel Baird MIT Licence

local table = require("table")
local io = require("io")
local class = require("core.class")

local pairs, ipairs, next, setmetatable = pairs, ipairs, next, setmetatable

return class(function (pool)

	function pool:init(metatable_or_constructor, destructor)
		self.free_objects = {}
		self.active_objects = {}
		
		if type(metatable_or_constructor) == "table" then
			self.constructor = function ()
				local new_obj = {}
				setmetatable(new_obj, metatable_or_constructor)
			end
		elseif type(metatable_or_constructor) == "function" then
			self.constructor = metatable_or_constructor
		else
			self.constructor = function ()
				return {}
			end
		end
		self.destructor = destructor
	end
	
	function pool:preallocate(size)
		local current_size = self:active_count() + self:free_count()
		while (current_size < size) do
			local obj = self.constructor()
			self.free_objects[obj] = obj
			current_size = current_size + 1
		end
		return self
	end
	
	function pool:acquire()
		local obj = next(self.free_objects)
		if obj then
			self.free_objects[obj] = nil
		else
			obj = self.constructor()
		end

		self.active_objects[obj] = obj
		return obj
	end
	
	function pool:release(obj)
		self.active_objects[obj] = nil
		if self.destructor then
			self.destructor(obj)
		end
		self.free_objects[obj] = obj
	end

	function pool:release_all()
		for obj, _ in pairs(self.active_objects) do
			self.active_objects[obj] = nil
			if self.destructor then
				self.destructor(obj)
			end
			self.free_objects[obj] = obj
		end
	end
	
	function pool:with_active(lambda)
		for k, _ in pairs(self.active_objects) do
			lambda(k)
		end
	end

	function pool:with_free(lambda)
		for k, _ in pairs(self.free_objects) do
			lambda(k)
		end
	end

	function pool:active_is_empty()
		local obj = next(self.active_objects)
		return obj == nil
	end

	function pool:active_count()
		local count = 0
		for k, _ in pairs(self.active_objects) do
			count = count + 1
		end
		return count
	end

	function pool:free_is_empty()
		local obj = next(self.free_objects)
		return obj == nil
	end

	function pool:free_count()
		local count = 0
		for k, _ in pairs(self.free_objects) do
			count = count + 1
		end
		return count
	end	
end)