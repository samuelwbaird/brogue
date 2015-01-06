-- runner model
-- copyright 2014 Samuel Baird MIT Licence

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
		
		if #possible == 0 then
			return nil
		end
		
		-- bias towards further positions
		possible:sort(function (p1, p2)
			return p1.row > p2.row
		end)
		
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
		
		-- otherwise the best clear space
		for distance = 4, 1, -1 do
			-- take a speed square first if available
			for _, pos in ipairs(possible) do
				if pos.speed_square and not pos:adjacent_blocker(distance) then
					return pos
				end
			end
			-- or just anything
			for _, pos in ipairs(possible) do
				if not pos.speed_square and not pos:adjacent_blocker(distance) then
					return pos
				end
			end
		end
		
		-- otherwise don't move
		return nil
	end

end)