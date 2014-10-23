-- convention around creating modules
-- copyright 2014 Samuel Baird MIT Licence

local module_constructor_functions = {
}

local function module(module_constructor, ...)
	local module_meta = {
	}
	module_meta.__index = module_constructor_functions;	-- add static module building functions to meta
	
	local module_table = {}
	setmetatable(module_table, module_meta)
	if module_constructor then
		module_constructor(module_table, ...)
	end
	
	-- add default call ability to create a fresh module, to avoid shared state when preferred
	module_meta.__call = function(module_table, ...)
		return module(module_constructor, ...)
	end
	
	return module_table
end

return setmetatable({ new = module }, {
	__call = function(module_module, ...)
		return module_module.new(...)
	end
})
