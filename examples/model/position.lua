-- position model
-- copyright 2014 Samuel Baird MIT Licence

local math = require('math')

local module = require('core.module')
local array = require('core.array')

return module(function (position)

	function position:define_class(model)
		model:define_class('position', {
			field_id = 'ID',
			name = 'TEXT',
		})
	end
	
	function position:define_relationships(model)
		-- a relationship to the field, inverse of field.positions
		model.position:define_relationship('field', model.field, 'field_id')

		-- all blockers at this position
		model.position:define_collection('blockers', model.blocker, 'position_id')
		
		-- all runners at this position
		model.position:define_collection('runners', model.runner, 'position_id')
		
		
		model.position:define_method('is_occupied', position.is_occupied)
		model.position:define_method('has_blocker', position.has_blocker)
		model.position:define_method('has_runner', position.has_runner)
		model.position:define_method('adjacent_randomised', position.adjacent_randomised)
		model.position:define_method('adjacent_runner', position.adjacent_runner)
		model.position:define_method('adjacent_runners', position.adjacent_runners)
		model.position:define_method('adjacent_blocker', position.adjacent_blocker)
		model.position:define_method('display', position.display)
		
		model.position:define_method('externalise', position.externalise)
	end
	
	-- these functions called as methods of ORM instances --
	
	function position:is_occupied()
		for runner in self:runners() do
			return true
		end
		for blocker in self:blockers() do
			return true
		end
		return false
	end
	
	function position:has_blocker()
		return #self:blockers(true) > 0
	end
	
	function position:has_runner()
		return #self:runners(true) > 0
	end
	
	function position:adjacent_randomised()
		local copy = array(self.adjacent)
		local random = array()
		while #copy > 0 do
			local i = math.random(1, #copy)
			random:push(copy[i])
			copy:remove(i)
		end
		return random
	end
	
	function position:adjacent_blocker(distance)
		distance = distance or 1
		local r = self:adjacent_randomised()
		
		for  _, p in ipairs(r) do
			if p:has_blocker() then
				return p:blockers(true)[1]
			end
		end
		if distance > 1 then
			for _, p in ipairs(r) do
				local r = p:adjacent_blocker(distance - 1)
				if r then
					return r
				end
			end
		end
		return nil
	end
	
	function position:adjacent_runner(distance)
		distance = distance or 1
		local r = self:adjacent_randomised()
		
		-- bias towards further runners
		r:sort(function (p1, p2)
			return p1.row > p2.row
		end)
		
		for  _, p in ipairs(r) do
			if p:has_runner() then
				return p:runners(true)[1]
			end
		end
		if distance > 1 then
			for _, p in ipairs(r) do
				local r = p:adjacent_runner(distance - 1)
				if r then
					return r
				end
			end
		end
		return nil
	end
	
	function position:adjacent_runners()
		local r = array()
		for  _, p in ipairs(self.adjacent) do
			for runner in p:runners() do
				r:push(runner)
			end
		end
		return r
	end
	
	function position:display()
		-- if there is a runner or blocker at this position then show them
		for runner in self:runners() do
			return runner.name
		end
		for blocker in self:blockers() do
			return blocker.name
		end
		if self.speed_square then
			return '# '
		else
			return '. '
		end
	end
	
	function position:externalise()
		local out = {
			name = self.name,
			speed = self.speed_square
		}
		for runner in self:runners() do
			out.runner = runner.name
		end
		for blocker in self:blockers() do
			out.blocker = blocker.name
		end
		return out
	end

end)