-- the main micro server running the game simulation
-- copyright 2014 Samuel Baird MIT Licence

local os = require('os')
local math = require('math')

local class = require('core.class')
local array = require('core.array')
local model = require('dweeb.model')

math.randomseed(os.time())

return class(function (game_thread)
	local super = game_thread.new
	
	function game_thread.new(db_path)
		local self = super()
		self:load_model(db_path)
		
		-- define an API to query and update the game
		local rep_api_description = {
			state = '-> *'
		}
		proxy_server(self, rep_api_description, 'inproc://game.query', zmq.REP, 'game.query')

		-- define a second API to pub/sub updates to the state
		local pub_api_description = {
			state_update = 'messages:*, state:*'
		}
		-- self.publish = proxy_server(self, pub_api_description, 'inproc://game.pub', zmq.PUB, 'game.pub')
		
		-- this server will run a normal coms event loop
		-- and also a main timer to update the game state
		-- update the game tick
		loop:add_interval(1000 * 3, function ()
			self:game_tick()
		end)

		return self
	end
	
	-- api methods
	
	function game_thread:state()
		-- define a view and the ability to project
		-- orm objects onto the view in some consistent manner
		-- then can share views across to worker threads easily for API calls...
		-- the 'view' should hook up references at the other end id -> id
		
		-- or build HTML etc. in the main thread and don't separate...
		
		return self.field:externalise()
	end
		
	-- prepare model
	
	function game_thread:load_model(db_path)
		-- load the ORM model for runners vs blockers
		-- see orm.lua example for more comments
		log('open the model at ' .. db_path)
		self.model = model(db_path)
		local model_classes = { 'field', 'position', 'blocker', 'runner' }
		for _, class in ipairs(model_classes) do
			require('model.' .. class):define_class(self.model)
		end
		for _, class in ipairs(model_classes) do
			require('model.' .. class):define_relationships(self.model)
		end
		
		-- this game is going to share a single field among all players let's create one here
		-- create a field and populate positions
		-- data updates must occur in a transaction
		
		self.model:transaction(function (self)
			self.field = self.model.field:create({
				state = 'finished',
			})
			self.field:create_all_positions()
			self.field:reset()
			log('created field ' .. self.field.id)
		end, self)
	end
	
	-- main game tick
	
	function game_thread:game_tick()
		if self.field.state == 'finished' then
			-- reset positions and turns
			self.model:transaction(function ()
				self.field:reset()
			end)

		elseif self.field.state == 'game' then
			local next = self.field.turns[1]
			if true or next.class_name == 'blocker' then
				local move = next:get_move()

				self.model:transaction(function (self)
					local trace = self.field:apply_move(move)
					-- trace:push(self.field:display())
					-- log(table.concat(trace, '\n'))
				end, self)
			end
		end	
		
	end
	
end)