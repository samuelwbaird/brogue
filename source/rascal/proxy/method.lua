-- method level definition of an API
-- proxy objects push method calls out to the network
-- send and receive of these calls all revolve around an API definition
-- copyright 2014 Samuel Baird MIT Licence

local string = require('string')

-- core modules
local class = require('core.class')
local array = require('core.array')

local parameter = require('rascal.proxy.parameter')

return class(function (method)
	
	function method:init(name, parameter_descriptions)
		self.name = name

		-- split the string into parameters and return type
		local parameter_part, return_part = parameter_descriptions:match('^(.-)%s*%-%>%s*(.+)$')
		if not parameter_part then
			parameter_part = parameter_descriptions
		end
		-- split all the parameters by comma
		self.parameters = array()
		for parameter_description in parameter_part:gmatch('%s*([^,]+)%s*,?%s*') do
			self.parameters:push(parameter(parameter_description))
		end
		-- document return type if present
		if return_part then
			self.return_type = parameter('return:' .. return_part)
		end
		self.void = (self.return_type == nil)
	end
	
end)