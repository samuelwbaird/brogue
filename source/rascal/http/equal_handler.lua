-- a handler that responds to an exact URL
-- chaining other handlers to that URL
-- copyright 2014 Samuel Baird MIT Licence

-- standard lua
local string = require('string')

-- core modules
local class = require('core.class')
local array = require('core.array')

return class(function (equal)

	function equal:init(url_path)
		self.url_path = url_path
	end
	
	function equal:handle(request, context, response)
		if request.url_path == self.url_path then
			return true
		else
			return false
		end
	end
end)