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
	end

end)