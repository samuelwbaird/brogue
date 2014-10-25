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
	end

end)