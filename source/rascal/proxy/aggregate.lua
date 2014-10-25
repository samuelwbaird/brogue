-- aggregates several proxy objects with distinct method calls into a single proxy object
-- copyright 2014 Samuel Baird MIT Licence

-- core modules
local class = require('core.class')
local array = require('core.array')

return class(function (aggregate)
	local super = aggregate.new
	
	function aggregate.new(proxy_array)
		local self = super()
		-- assumes a list of proxy objects with : syntax methods
		for _, proxy in ipairs(proxy_array) do
			for method_name, method_function in pairs(proxy) do
				if type(method_function) == 'function' then
					self[method_name] = function (self, ...)
						return proxy[method_name] (proxy, ...)
					end
				end
			end
		end
		return self
	end

end)