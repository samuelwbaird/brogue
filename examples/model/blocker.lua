-- blocker model
-- copyright 2014 Samuel Baird MIT Licence

local math = require('math')

local module = require('core.module')
local array = require('core.array')

return module(function (blocker)

	function blocker:define_class(model)
		model:define_class('blocker', {
			name = 'TEXT',
			field_id = 'ID',
			position_id = 'ID',
		})
	end
	
	function blocker:define_relationships(model)
		model.blocker:define_relationship('field', model.field, 'field_id')
		model.blocker:define_relationship('position', model.position, 'position_id')
		model.blocker:define_method('get_move', blocker.get_move)
	end
	
	-- these functions called as methods of ORM instances --
	
	-- return the position this blocker should move to
	function blocker:get_move()
		-- find all unoccupied adjacent positions and pick one
		local possible = array()
		for _, pos in ipairs(self.position:adjacent_randomised()) do
			if not pos:is_occupied() then
				possible:push(pos)
			end
		end

		if #possible == 0 then
			-- cannot move
			return nil
		end
		
		-- could also stay here
		possible:push(self.position)
		
		-- check for a likely runner to chase
		for distance = 1, 3 do
			for _, pos in ipairs(possible) do
				local r = pos:adjacent_runner(distance)
				if r then
					return pos
				end
			end
		end
		
		-- otherwise go random
		return possible[math.random(1, #possible)]
	end


end)