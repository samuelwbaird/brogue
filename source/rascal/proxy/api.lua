-- core modules
local class = require('core.class')
local array = require('core.array')

local method = require('rascal.proxy.method')

return class(function (api)
	local super = api.new
	
	function api.new(api_description)
		local self = super()
		self.methods = array()
		self.method = {}
		
		for method_name, description in pairs(api_description) do
			local m = method(method_name, description)
			self.method[method_name] = m
			self.methods:push(m)
		end
		
		return self
	end
	
	-- iterate methods
	-- iterate parameters
	-- output code to validate a parameter
	-- output code to assemble and dissemble parameters
	-- output code to call functions
	
end)