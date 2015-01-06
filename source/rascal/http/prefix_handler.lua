-- a handler that responds to a specified prefix in the URL
-- chaining other handlers to handle the rest of the URL path
-- copyright 2014 Samuel Baird MIT Licence

-- standard lua
local string = require('string')

-- core modules
local class = require('core.class')
local array = require('core.array')

return class(function (prefix)
	local super = prefix.new

	function prefix.new(url_prefix)
		local self = super()
		self.url_prefix = url_prefix
		return self
	end
	
	function prefix:handle(request, context, response)
		if request.url_path:sub(1, #self.url_prefix) == self.url_prefix then
			-- if found the remove prefix from the path, storing the original url
			if #request.url_path > #self.url_prefix then
				request:rewrite_url_path(request.url_path:sub(#self.url_prefix + 1))
			else
				request:rewrite_url_path('')
			end
			return true
		else
			return false
		end
	end
end)