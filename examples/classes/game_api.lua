-- a custom handler that demonstrates serving API method calls
-- copyright 2014 Samuel Baird MIT Licence

local class = require('core.class')
local array = require('core.array')

local rascal = require('rascal.core')

return class(function (game_api)
	local super = game_api.new

	function game_api.new()
		local self = super()
		-- connect to proxies
		return self
	end
	
	function game_api:handle(request, context, response)
		-- check for the api method to be called
		local method = request.url_path
		-- remove trailing slash from method
		method = method:match('(.-)/$') or method
				
		-- check for json input
		local input = request:json()
		
		if method == 'poll' then
			local out = {
				content = 'poll from ' .. context.session_data.name
			}
			if input then
				for k, v in pairs(input) do
					out[k] = v
				end
			end
			response:set_json(out)
		end
		
		return true
	end
end)