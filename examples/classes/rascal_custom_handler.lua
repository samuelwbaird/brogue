package.path = '../source/?.lua;' .. package.path

-- a custom handler for rascal, run rascal_custom_world.lua to use this
-- responds with the current unixtime

require('os')

local class = require('core.class')
local rascal = require('rascal.core')

return class(function (rascal_custom_handler)
	
	function rascal_custom_handler:handle(request, context, response)
		-- our custom handler respond with some dynamic content
		response:set_mimetype_from_extension('html')
		response:set_body('The unixtime is ' .. os.time())
			
		-- invoke the rest of the chain
		return true
	end
end)