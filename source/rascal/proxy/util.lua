-- utility functions for proxy objects
-- copyright 2014 Samuel Baird MIT Licence

local string = require('string')
local table = require('table')

local cmsgpack = require('cmsgpack')

-- core modules
local module = require('core.module')

-- rascal
local rascal = require('rascal.core')
local api = require('rascal.proxy.api')

return module(function (util)
	
	local connection_pool = {}
	
	function util.get_connection(connection)
		-- add connections to a pool of connections
		if not connection_pool[connection] then
			connection_pool[connection] = rascal.registry:connect(connection)
		end
		return connection_pool[connection]
	end
	
	function util.pass_through(connection, method_name, target, target_api_description)
		local client = util.get_connection(connection)		
		target_api_description[method_name] = client.api_description[method_name]
		target[method_name] = function (self, ...)
			return client[method_name](client, ...)
		end
	end
	
end)