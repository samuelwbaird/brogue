-- a handler that can be used to populate a template
-- directly from the request and context tables
-- copyright 2014 Samuel Baird MIT Licence

-- core modules
local class = require('core.class')
local template = require('rascal.util.template')

require('rascal.base')

return class(function (static)

	function static:init(filename, extension)
		self.extension = extension or 'html'
		self.template = template.from_file(filename)
	end
	
	function static:handle(request, context, response)
		-- our custom handler respond with some dynamic content
		response:set_mimetype_from_extension(self.extension)
		response:set_body(self.template({
			request = request,
			context = context,
			response = response
		}))
			
		-- we have handled the request
		return true
	end
end)