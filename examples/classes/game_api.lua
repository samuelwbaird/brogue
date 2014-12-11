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
		rascal.registry:connect_sub('game.pub', self)
		
		-- pretending to treat each client as distinct
		self.fake_id_counter = 0
		self.defer_list = array()

		return self
	end
	
	function game_api:signal_update()
		self.defer_list:with_each(function (defer)
			defer.worker:signal(defer.fake_id)
		end)
		self.defer_list = array()
	end
	
	function game_api:handle(request, context, response)
		-- check for the api method to be called
		local method = request.url_path
		-- remove trailing slash from method
		method = method:match('(.-)/$') or method
				
		-- check for json input
		local input = request:json()
		if method == 'move' then
			local turn_no = input.turn_no or 0
			local position = input.position or ''
			local result = self.game_query:move(turn_no, position)
			if result == true then
				response:set_json("your moved to " .. position)
			else
				response:set_json(result)
			end
			
		elseif method == 'poll' then
			-- check the last state query, if it matches the current state then queue for long poll
			local last_seen = input.move
			if last_seen == self.game_query:last() then
				self.fake_id_counter = self.fake_id_counter + 1
				self.defer_list:push({
					fake_id = self.fake_id_counter,
					worker = context.http_worker
				})
				context.http_worker:defer(self.fake_id_counter, request, context, response)
			else
				response:set_json(self.game_query:state())
			end
		end
		
		return true
	end
end)