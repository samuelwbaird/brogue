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
		
		self.game_query = rascal.registry:connect('game.query')
		
		return self
	end
	
	function game_api:handle(request, context, response)
		-- check for the api method to be called
		local method = request.url_path
		-- remove trailing slash from method
		method = method:match('(.-)/$') or method
				
		-- check for json input
		local input = request:json()
		if method == 'move' then
			local turn = input.turn_no or 0
			local position = input.position or ''
			response:set_json({
				turn_no = turn,
				position = position,
			})
			
		elseif method == 'poll' then
			response:set_json(self.game_query:state())
		end
		
		return true
	end
end)