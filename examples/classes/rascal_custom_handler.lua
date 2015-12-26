-- a custom handler for rascal, run rascal_custom_world.lua to use this
-- responds with the current unixtime
-- copyright 2014 Samuel Baird MIT Licence

package.path = '../source/?.lua;' .. package.path

require('os')

local class = require('core.class')
local rascal = require('rascal.core')
local html = require('rascal.util.html')

return class(function (rascal_custom_handler)	
	function rascal_custom_handler:handle(request, context, response)
		-- our custom handler respond with some dynamic content
		response:set_mimetype_from_extension('html')

		-- build an HTML document
		local doc = html()
		doc:add_h1('Unixtime Report')
		
		--doc:h1().text = 'testing'
		
		-- add atable
		local t = doc:add_table()
		t:add_td('Right now')
		t:add_td(os.time())
		
		-- set the document as the body of the response
		response:set_body(doc)
			
		-- invoke the rest of the chain
		return true
	end
end)