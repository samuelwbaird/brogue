-- a handler that responds to a match (using Lua pattern matching)
-- chaining other handlers to handle the matched pattern
-- copyright 2014 Samuel Baird MIT Licence

-- standard lua
local string = require('string')

-- core modules
local class = require('core.class')
local array = require('core.array')

return class(function (match)
	local super = match.new

	function match.new(url_match)
		local self = super()
		self.url_match = url_match
		return self
	end
	
	function match:handle(request, context, response)
		local match = request.url_path:match(self.url_match)
		if match then
			request:rewrite_url_path(match)
			request.url_path = match
			return true
		else
			return false
		end
	end
end)