-- top level definition of an API
-- proxy objects push method calls out to the network
-- send and receive of these calls all revolve around an API definition
-- copyright 2014 Samuel Baird MIT Licence

-- TODO: api_description format needs documenting ASAP

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
	
end)