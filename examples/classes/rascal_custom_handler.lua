package.path = '../source/?.lua;' .. package.path

-- a custom handler for rascal, run rascal_custom_world.lua to use this
-- responds with the current unixtime

require('os')

local class = require('core.class')
local rascal = require('rascal.core')
local template = require('rascal.util.template')

return class(function (rascal_custom_handler)
	local super = rascal_custom_handler.new
	
	function rascal_custom_handler.new()
		local self = super()
		self.template = template.from_string([[
The unixtime is {time}]])
		return self
	end
	
	function rascal_custom_handler:handle(request, context, response)
		-- our custom handler respond with some dynamic content
		response:set_mimetype_from_extension('html')
		response:set_body(self.template({
			time = os.time()
		}))
			
		-- invoke the rest of the chain
		return true
	end
end)