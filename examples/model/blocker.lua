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
	end

end)