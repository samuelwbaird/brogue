-- core modules
local class = require('core.class')

return class(function (parameter)
	local super = parameter.new
	
	function parameter.new(parameter_description)
		local self = super()

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
		
		return self
	end
	
end)