-- standard lua
local string = require('string')

-- core modules
local class = require('core.class')
local array = require('core.array')

return class(function (equal)
	local super = equal.new

	function equal.new(url_path)
		local self = super()
		self.url_path = url_path
		return self
	end
	
	function equal:handle(request, context, response)
		if request.url_path == self.url_path then
			return true
		else
			return false
		end
	end
end)