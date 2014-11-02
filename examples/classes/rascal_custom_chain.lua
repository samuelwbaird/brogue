-- a custom request chain handler for rascal, run rascal_custom_world.lua to use this
-- outputs the request url and all headers to the log, on every request
-- copyright 2014 Samuel Baird MIT Licence

package.path = '../source/?.lua;' .. package.path

local class = require('core.class')
local rascal = require('rascal.core')

return class(function (rascal_custom_chain)
	
	function rascal_custom_chain:handle(request, context, response)
		-- our custom handler will log some info then invoke the rest of the chain
		log('custom handler ' .. request.url)
		for k, v in pairs(request.headers) do
			log(k .. ' : ' .. v)
		end
			
		-- invoke the rest of the chain
		return true
	end
end)