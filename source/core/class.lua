-- convention around creating simple metatable class types
-- no inheritance, data hiding built in
-- copyright 2014 Samuel Baird MIT Licence

local class_meta = {
	-- constructor callable directly off the class
	__call = function(class, ...)
		return class.new(...)
	end,
	-- class static meta methods
	__index = {
		mixin = function (self, other_class)
			-- "inherit" the values if applicable
			for k, v in pairs(other_class) do
				if self[k] == nil then
					self[k] = v
				end
			end
		end,
		
		-- lazily construct some properties
		lazy = function (class, lazy_property_constructors)
			-- replace the class __index with an interceptor to create lazy properties as required
			local old_index = class.__index
			class.__index = function (obj, name)
				-- intersect with lazy constructor
				if lazy_property_constructors[name] then
					local val = lazy_property_constructors[name]()
					rawset(obj, name, val)
					return val
				end
				if old_index then
					if type(old_index) == "table" then
						-- delegate to prior table and promote
						local val = old_index[name]
						if val then
							rawset(obj, name, val)
						end
						return val
					else
						-- must be a function
						old_index(obj, name)
					end
				end
			end
		end,
	}
}

local function class(class_constructor)
	local meta = {}
	meta.__index = meta
	
	function meta.new(...)
		local self = setmetatable({}, meta)
		if meta.init then
			return self:init(...) or self
		else
			return self
		end
	end
	
	function meta.is_member(obj)
		return obj and getmetatable(obj) == meta
	end
	
	setmetatable(meta, class_meta)

	-- define this class
	if class_constructor then
		class_constructor(meta)
	end
	
	
	return meta
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

return setmetatable({ new = class, derive = derive, package = package }, class_meta)
