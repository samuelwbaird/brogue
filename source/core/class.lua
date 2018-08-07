-- convention around creating simple metatable class types
-- no inheritance, data hiding built in
-- copyright 2016 Samuel Baird MIT Licence

local meta = require('core.meta')

local class_meta = {
	-- constructor callable directly off the class
	__call = function(class, ...)
		return class.new(...)
	end,
	-- shared class static methods
	__index = {
		-- copy the methods/values of another class
		mixin = function (self, other_class)
			for k, v in pairs(other_class) do
				if k ~= '__newindex' then
					if self[k] == nil then
						self[k] = v
					end
				end
			end
			-- copy in property functionality if present
			if next(other_class._properties) then
				self:enable_full_index()
				self:enable_full_newindex()
			end
			-- merge property list
			for k, v in pairs(other_class._properties) do
				if self._properties[k] == nil then
					self._properties[k] = v
				end
			end
		end,

		-- enable the full functionality index metamethod if it is required for this class
		enable_full_index = function (class)
			if class.__index == class then
				class.__index = class.__fullindex
			elseif class.__index == class.__fullindex then
				-- nothing to do
			else
				error('cannot enable full index metamethod after override', 3)
			end		
		end,
		
		-- enable the full functionality newindex metamethod if it is required for this class
		enable_full_newindex = function (class)
			if class.__newindex == nil then
				class.__newindex = class.__fullnewindex
			elseif class.__newindex == class.__fullnewindex then
				-- nothing to do
			else
				error('cannot enable full newindex metamethod after override', 3)
			end		
		end,
		
		-- add a property, optional getter and setter
		-- getter (obj) -> value
		-- setter (obj, value) -> void
		add_property = function (class, name, getter, setter)
			class:enable_full_index()
			class:enable_full_newindex()
			class._properties[name] = {
				getter = getter,
				setter = setter,
			}
		end,

		-- add a property that is inflated or created the first time it is read
		add_lazy_property = function (class, name, inflater)
			class:enable_full_index()
			class._properties[name] = {
				getter = function (obj)
					-- inflate and set this as a simple value from now on
					local value = inflater()
					rawset(obj, name, value)
					return value
				end,
				setter = nil,
			}
		end,
		
		-- make this class strict, reads from unknown properties are errors
		strict = function (class)
			class:enable_full_index()
			class._strict = true
		end,

		-- make this class sealed, writes to unknown properties are errors (use rawset for private/internal rights)
		seal = function (class)
			class:enable_full_newindex()
			class._sealed = true
		end,
	}
}

local function class(class_constructor)
	local class = {}
	setmetatable(class, class_meta)

	-- by default supply lightweight meta methods
	class.__index = class
	class.__newindex = nil

	-- if the class uses particular features these full meta method might be required
	class._properties = {}
	class._sealed = false
	class._strict = false
	function class.__fullindex(object, property)
		-- check for property value or getters
		local prop = class._properties[property]
		if prop then
			if prop.getter then
				return prop.getter(object)
			else
				error('property ' .. tostring(property) .. ' cannot be read', 2)
			end
		end
		-- otherwise allow default behaviour
		local value = class[property]
		-- handle strict
		if not value and class._strict then
		 	error('cannot read unknown property ' .. tostring(property) .. ' class is strict', 2)
		end
		return value
	end
	function class.__fullnewindex(object, property, value)
		-- check for property setters
		-- check for property value or getters
		local prop = class._properties[property]
		if prop then
			if prop.setter then
				return prop.setter(object, value)
			else
				error('property ' .. tostring(property) .. ' cannot be set', 2)
			end
		end
		-- handle sealed
		if class._sealed then
		 	error('cannot set property ' .. tostring(property) .. ' class is sealed', 2)
		end
		-- otherwise allow default behaviour
		rawset(object, property, value)
	end
	
	-- class specific methods
	function class.new(...)
		local self = setmetatable({}, class)
		if class.init then
			return self:init(...) or self
		else
			return self
		end
	end

	function class.has_instance(obj)
		return obj and getmetatable(obj) == class
	end
	
	function class.delegate(obj, method)
		return function (...)
			method(obj, ...)
		end
	end

	-- let the caller define this class
	if class_constructor then
		class_constructor(class)
	end
	
	return class
end

local function derive(base, class_constructor)
	return class(function (derived)
		derived:mixin(base)
		class_constructor(derived)
	end)
end

local function package(publish_these_classes_and_functions, default_constructor)
	local unique = {}
	local publish = {}
	
	for k, v in pairs(publish_these_classes_and_functions) do
		-- named entries are public as named
		if type(k) == "string" then
			publish[k] = v
		end
		-- entries that are tables are scanned for unique names and these are promoted to public
		if type(v) == "table" then
			for tk, tv in pairs(v) do
				if unique[tk] == nil then
					unique[tk] = tv
				else
					unique[tk] = false
				end
			end
		end
	end
	
	for k, v in pairs(unique) do
		if publish[k] == nil and v ~= false then
			publish[k] = v
		end
	end
	
	if default_constructor then
		setmetatable(publish, {
			__call = function (meta,  ...)
				return default_constructor(...)
			end
		})
	end
	
	return publish
end

return package({ class = class, derive = derive, package = package }, class)