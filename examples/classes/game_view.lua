package.path = '../source/?.lua;' .. package.path

-- a custom handler that's going to serve the game view as dynamic html

local class = require('core.class')
local array = require('core.array')
local rascal = require('rascal.core')

return class(function (game_view)
	
	function game_view:handle(request, context, response)
		-- our custom handler respond with some dynamic content
		response:set_mimetype_from_extension('html')
		
		local out = array()
		out:push('<html><head><title>Runners vs Blockers</title></head><body>')
		out:push('<h1>You are player ' .. context.session_data.name .. '</h1>')
		out:push('</body></html>')
		
		response:set_body(out:concat())
			
		-- invoke the rest of the chain
		return true
	end
end)