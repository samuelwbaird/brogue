-- a custom handler that's going to serve the game view as dynamic html
-- copyright 2014 Samuel Baird MIT Licence

package.path = '../source/?.lua;' .. package.path


local class = require('core.class')
local array = require('core.array')
local rascal = require('rascal.core')
local template = require('rascal.util.template')

return class(function (game_view)

	function game_view:init()
		self.template = template.from_file('templates/game_view.html')
	end
		
	function game_view:handle(request, context, response)
		-- our custom handler respond with some dynamic content
		response:set_mimetype_from_extension('html')
		response:set_body(self.template({
			name = context.session_data.name,
		}))
			
		-- we have handled the request
		return true
	end
end)