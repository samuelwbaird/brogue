local string = require('string')

-- core modules
local class = require('core.class')
local array = require('core.array')

local parameter = require('rascal.proxy.parameter')

return class(function (method)
	local super = method.new
	
	function method.new(name, parameter_descriptions)
		local self = super()
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
		
		return self
	end
	
end)