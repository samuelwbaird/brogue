-- create a client to a published API
-- the api_description is used to create new methods on the fly
-- that validate parameters and marshall data using cmsgpack across the 0MQ channels
-- marshalling is transparent to the caller of the API
--
-- some APIs are request/response, and the proxy will block on the response
-- other APIs are publish/push, and the proxy return nil without blocking
--
-- copyright 2014 Samuel Baird MIT Licence


local string = require('string')
local table = require('table')

local cmsgpack = require('cmsgpack')

-- core modules
local class = require('core.class')
local array = require('core.array')

-- rascal
require('rascal.base')
local api = require('rascal.proxy.api')

return class(function (proxy)
	
	function proxy:init(channel, socket_type, api_description)
		-- prep the coms
		self.channel = channel
		self.socket_type = socket_type
		self.socket = ctx:socket(socket_type)
		self.socket:connect(channel)
		-- proxy all the methods of the api_description
		local api = api(api_description)
		for _, method in ipairs(api.methods) do
			self[method.name] = proxy.create_proxy_method(method.name, socket_type, method)
		end
		self.api = api
		self.api_description = api_description
	end
	
	function proxy.create_proxy_method(name, socket_type, method)
		local method_code = array()

		-- add a preamble where this is a function call with named ordered args
		local arg_names = array()
		arg_names:push('self')
		for _, parameter in ipairs(method.parameters) do
			arg_names:push(parameter.name)
		end
		method_code:push('local ' .. table.concat(arg_names, ', ') .. ' = ...')
		
		-- TODO: add api_description code to verify each parameter
		for _, parameter in ipairs(method.parameters) do
			method_code:push('-- TODO: verify ' .. parameter.name)
		end
		
		-- prep the parameters for sending
		method_code:push('params = {}')
		for _, parameter in ipairs(method.parameters) do
			method_code:push('params.' .. parameter.name .. ' = ' .. parameter.name)
		end
		method_code:push('self.socket:send_all({')
		method_code:push('  \'' .. name .. '\',')
		method_code:push('  cmsgpack.pack(params),')
		method_code:push('})')
		
		-- do we need to read a response from the socket
		if socket_type == zmq.REQ then
			method_code:push('local response = self.socket:recv_all()')
			-- method_code:push('if response and #response == 1 then')
			-- method_code:push('  return cmsgpack.unpack(response[1])')
			-- method_code:push('end')

			-- TODO: does the api description have a return type, we could validate it
			-- check for error codes returned
			method_code:push('if response and #response == 1 then')
			method_code:push('  local response = cmsgpack.unpack(response[1])')
			method_code:push('  if response and type(response) == "table" and type(response.success) == "boolean" then')
			method_code:push('		if response.success then')
			method_code:push('			return response.result')
			method_code:push('		else')
			method_code:push('			error(response.result, 2)')
			method_code:push('		end')
			method_code:push('	end')
			method_code:push('	return response')
			method_code:push('end')
		end

		local code = table.concat(method_code, '\n')
		local proxy_method, compile_error = loadstring(code, 'proxy_client::' .. name)
		if not proxy_method then
			error('error creating proxy ' .. compile_error .. '\n' .. code)
		end
		return proxy_method
	end
	
end)