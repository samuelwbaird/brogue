-- parameter level definition of an API
-- proxy objects push method calls out to the network
-- send and receive of these calls all revolve around an API definition
-- copyright 2014 Samuel Baird MIT Licence

-- core modules
local class = require('core.class')

return class(function (parameter)
	
	function parameter:init(parameter_description)
		-- split into name + qualifiers
		local name_part, qualifiers_part = parameter_description:match('^(.-)%s*%:%s*(.+)$')
		if not name_part then
			name_part = parameter_description
		end
		if not qualifiers_part then
			qualifiers_part = '*'
		end
		self.name = name_part
		
		-- split all the qualifiers by colon
		self.qualifiers = {}
		for qualifier in qualifiers_part:gmatch('%s*([^%:]+)%s*%:?%s*') do
			self.qualifiers[qualifier] = qualifier
		end
	end
	
end)