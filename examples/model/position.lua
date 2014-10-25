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
		model.position:define_method('display', position.display)
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
	
	function position:display()
		-- if there is a runner or blocker at this position then show them
		for runner in self:runners() do
			return runner.name
		end
		for blocker in self:blockers() do
			return blocker.name
		end
		return '. '
	end

end)