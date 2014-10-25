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
		for _, pos in ipairs(self.position:adjacent_randomised()) do
			if not pos:is_occupied() then
				possible:push(pos)
			end
		end
		
		-- move to any position that is on row 7
		for _, pos in ipairs(possible) do
			if pos.row == 7 then
				return pos
			end
		end
		
		-- or is forward and has no blocker within 2
		for _, pos in ipairs(possible) do
			if pos.row > self.position.row and not pos:adjacent_blocker(2) then
				return pos
			end
		end		
		
		-- sometimes take a risk moving forward with safety in numbers
		--if false and math.random(1, 2) == 1 then
			for _, pos in ipairs(possible) do
				if pos.row > self.position.row and not pos:adjacent_blocker(1) then
					return pos
				end
			end		
		--end
		
		-- or has no blocker within 2
		for _, pos in ipairs(possible) do
			if not pos:adjacent_blocker(2) then
				return pos
			end
		end
		
		-- otherwise don't move
		return nil
	end

end)