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

		-- this server will run a normal coms event loop
		-- and also a main timer to update the game state
		-- update the game tick
		loop:add_interval(1000 * 5, function ()
			self:game_tick()
		end)

		return self
	end
	
	function game_thread:load_model(db_path)
		-- load the ORM model for runners vs blockers
		-- see orm.lua example for more comments
		print('open the model at ' .. db_path)
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
			log('created field ' .. self.field.id .. '\n' .. self.field:display())
		end, self)
	end
	
	
	function game_thread:game_tick()
		log('game_thread:game_tick')
		
		if self.field.state == 'finished' then
			-- reset positions and turns
			self.model:transaction(function ()
				self.field:reset()
			end)
			log('reset\n' .. self.field:display())


		elseif self.field.state == 'game' then
			local next = self.field.turns[1]
			local move = next:get_move()
			log(next.name .. ' -> ' .. (move and move.name or 'no move'))

			self.model:transaction(function (self)
				local trace = self.field:apply_move(move)
				trace:push(self.field:display())
				log(table.concat(trace, '\n'))
			end, self)
		end	
		
	end
	
end)