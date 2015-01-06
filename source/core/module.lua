-- convention around creating modules
-- copyright 2014 Samuel Baird MIT Licence

local module_constructor_functions = {
}

local function module(module_constructor, ...)
	local module_meta = {
		-- add static module building functions to meta
		__index = module_constructor_functions,
		-- add default call ability to construct a fresh module
		__call = function(module_table, ...)
			return module(module_constructor, ...)
		end,
	}
	
	local module_table = {}
	setmetatable(module_table, module_meta)
	if module_constructor then
		module_constructor(module_table, ...)
	end
	
	return module_table
end

return setmetatable({ new = module }, {
	__call = function(module_module, ...)
		return module_module.new(...)
	end
})
