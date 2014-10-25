local math = require('math')

local module = require('core.module')
local array = require('core.array')

return module(function (runner)

	function runner:define_class(model)
		model:define_class('runner', {
			name = 'TEXT',
			field_id = 'ID',
			position_id = 'ID',
		})
	end
	
	function runner:define_relationships(model)
		model.runner:define_relationship('field', model.field, 'field_id')
		model.runner:define_relationship('position', model.position, 'position_id')
		model.runner:define_method('get_move', runner.get_move)
	end
	
	-- these functions called as methods of ORM instances --
	
	-- return the position this runner should move to
	function runner:get_move()
		-- find all unoccupied adjacent positions and pick one
		local possible = array()
		for _, pos in ipairs(self.position.adjacent) do
			if not pos:is_occupied() then
				possible:push(pos)
			end
		end

		if #possible == 0 then
			-- cannot move, blockers will win
			return nil
		end
		
		-- first pick a random position, if it is forward then take the move
		for i = 1, 2 do
			local p = possible[math.random(1, #possible)]
			if p.row > self.position.row then
				return p
			end
		end

		-- otherwise a random movement
		return possible[math.random(1, #possible)]
	end

end)