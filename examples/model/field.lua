local module = require('core.module')

local array = require('core.array')

return module(function (field)

	function field:define_class(model)
		model:define_class('field', {
			-- individual fields
		})
	end
	
	function field:define_relationships(model)
		-- a collection of positions, inverse of references back to this field
		model.field:define_collection('positions', model.position, 'field_id')
		model.field:define_collection('blockers', model.blocker, 'field_id')
		model.field:define_collection('runners', model.runner, 'field_id')

		-- map methods on the ORM instances onto functions in this module
		model.field:define_method('create_all_positions', field.create_all_positions)
		model.field:define_method('get_position', field.get_position)
		model.field:define_method('shift_turns', field.shift_turns)
		model.field:define_method('remove_runner', field.remove_runner)
		model.field:define_method('reset', field.reset)
		model.field:define_method('display', field.display)
	end
	
	-- these functions called as methods of ORM instances --
	
	function field:get_position(r, c)
		return self.model.position:get({
			field_id = self.id,
			name = '[' .. c .. ':' .. r .. ']'
		})
	end

	function field:create_all_positions()
		-- now create a grid of positions and populate the adjacent position and field
		local rows = array()
		for r = 1, 7 do
			rows[r] = array()
			for c = 1, 9 do
				rows[r][c] = self.model.position:create({
					-- set the reference back to the self (using the defined relationship)
					field = self,
					row = r,
					column = c,
					name = '[' .. c .. ':' .. r .. ']'
				})
				rows[r][c].speed_square = (r % 2 == 0 and c % 2 == 0)
			end
		end
	
		-- we can set some arbitrary value on the objects, even complex things
		-- like arrays of references to other objects, without defining them first
		for r = 1, 7 do
			for c = 1, 9 do
				-- get the list of valid adjacent positions
				local adjacent = array()
				for r_offset = -1, 1 do
					if r + r_offset >= 1 and r + r_offset <= #rows then
						for c_offset = -1, 1 do
							if c + c_offset >= 1 and c + c_offset <= #rows[r] then
								if rows[r + r_offset][c + c_offset] ~= rows[r][c] then
									adjacent:push(rows[r + r_offset][c + c_offset])
								end
							end
						end
					end
				end
				-- set an array of adjacent positions on this position
				rows[r][c].adjacent = adjacent
			end
		end
		
		-- now we create the blockers and runners for the game
		-- we set their reference to the field, so they will be in the field list of all runners and blockers
		-- but not associated with specified
		for i = 1, 4 do
			self.model.runner:create({
				name = 'r' .. i,
				field = self,
			})
		end
		for i = 1, 2 do
			self.model.blocker:create({
				name = 'b' .. i,
				field = self,
			})
		end
	end
	
	function field:shift_turns()
		local turns = self.turns
		local first = turns[1]
		table.remove(turns, 1)
		turns[#turns + 1] = first
		
		-- need to re-assign to the property for the model to pick up the changes
		self.turns = turns
	end
	
	function field:remove_runner(runner)
		runner.position = nil
		local turns = self.turns
		for i = 1, #turns do
			if turns[i] == runner then
				table.remove(turns, i)
				break
			end
		end
		-- need to re-assign to the property for the model to pick up the changes
		self.turns = turns
		
		-- have the blockers won?
		for runner in self:runners() do
			if runner.position then
				-- still runners on the field
				return false
			end
		end
		return true
	end

	function field:reset()
		-- field.state = 'game'
		local turns = array()
		local i = 0
		for runner in self:runners() do
			turns:push(runner)
			runner.position = self:get_position(1, 2 + (i * 2))
			i = i + 1
		end
		i = 0
		for blocker in self:blockers() do
			turns:push(blocker)
			blocker.position = self:get_position(6, 3 + (i * 4))
			i = i + 1
		end
		self.turns = turns
	end

	function field:display()
		local rows = array()
		for r = 1, 7 do
			rows[r] = array()
			for c = 1, 9 do
				rows[r][c] = '  '
				-- find the position object
				local pos = self:get_position(r, c)
				if pos then
					rows[r][c] = pos:display()
				end
			end
			rows[r] = table.concat(rows[r], ' ' )
		end
		-- show which turns are next
		rows[8] = array()
		for _, instance in ipairs(self.turns) do
			rows[8]:push(instance.name)
		end
		rows[8] = table.concat(rows[8], ' ')
		return table.concat(rows, '\n')
	end


end)