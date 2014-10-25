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
	end

end)