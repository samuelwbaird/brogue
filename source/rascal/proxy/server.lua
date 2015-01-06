-- create a server for a published API
-- the api_description is used to create new methods on the fly
-- that receive data from 0MQ channels, unpack and validate parameters
-- the methods are either published on a channel and to the registry
-- or bound to an existing 0MQ run loop
-- marshalling is transparent to the provider of the API
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
local client = require('rascal.proxy.client')

return class(function (proxy)
	local super = proxy.new

	function proxy.new(target, api_description, channel, socket_type, publish_service_id)
		local self = super()
		self.target = target
		self.api_description = api_description
		self.channel = channel
		self.socket_type = socket_type
		-- proxy all the methods of the api_description
		local api = api(api_description)
		if socket_type == zmq.PUB then
			-- target is not used
			for _, method in ipairs(api.methods) do
				self[method.name] = client.create_proxy_method(method.name, socket_type, method)
			end
		else
			for _, method in ipairs(api.methods) do
				self[method.name] = proxy.create_proxy_method(method.name, method)
			end
		end
		if channel and socket_type then
			self:bind(channel, socket_type)
			if socket_type == zmq.SUB then
				for _, method in ipairs(api.methods) do
					self.socket:subscribe(method.name)
				end
			end
		end
		if publish_service_id then
			self:publish(publish_service_id)
		end
		return self
	end
	
	function proxy:publish(publish_service_id, publish_socket_type)
		local rascal = require('rascal.core')
		if not publish_socket_type then
			if self.socket_type == zmq.PULL then
				publish_socket_type = zmq.PUSH
			elseif self.socket_type == zmq.PUB then
				publish_socket_type = zmq.SUB
			else
				publish_socket_type = zmq.REQ
			end
		end
		rascal.registry:publish(publish_service_id, self.channel, publish_socket_type, self.api_description)
	end
	
	function proxy:route_request(routing, command, params)
		local output = array()
		for _, r in ipairs(routing) do
			output:push(r)
		end
		output:push(command)
		output:push(cmsgpack.pack(params))
		self.socket:send_all(output)
	end
	
	function proxy:route_response(routing, response)
		local output = array()
		for _, r in ipairs(routing) do
			output:push(r)
		end
		output:push(cmsgpack.pack(response))
		self.socket:send_all(output)
	end
	
	function proxy:bind(channel, socket_type)
		-- prep the coms
		self.channel = channel
		self.socket_type = socket_type
		self.socket = ctx:socket(socket_type)
		if socket_type == zmq.SUB then
			self.socket:connect(channel)
		elseif socket_type == zmq.PUB then
			self.socket:bind(channel)
			return
		else
			self.socket:bind(channel)
		end
		
		-- add to loop
		loop:add_socket(self.socket, function (socket)
			local input = socket:recv_all()
			-- marshall the input
			-- any leading values are routing information
			local routing = array()
			for i = 1, #input - 2 do
				routing:push(input[i])
			end
			-- the last two are considered command + params
			local command = input[#input - 1]
			local params = cmsgpack.unpack(input[#input])

			-- call the function via the proxy			
			if socket_type == zmq.ROUTER then
				-- the incoming routing is stored as a ref on the proxy
				-- as this value only has meaning to the router that received it
				self.routing = routing
				-- routing is passed in as an additional parameter
				local success, result = pcall(self[command], self, params)
				if not success then
					log('error', result)
				end
			else
				local success, result = pcall(self[command], self, params)
				if not success then
					log('error', result)
				end
				-- return the result if required
				if socket_type == zmq.REP then
					local output = {
						cmsgpack.pack({
							success = success,
							result = result,
						})
					}
					socket:send_all(output)
				end
			end
		end)
	end
	
	function proxy.create_proxy_method(name, method)
		local method_code = array()

		-- add a preamble where self and the parameters are the input
		local arg_names = array()
		arg_names:push('self')
		arg_names:push('input')
		method_code:push('local ' .. table.concat(arg_names, ', ') .. ' = ...')
		
		-- make locals for all of the required fields
		arg_names = array()
		for _, parameter in ipairs(method.parameters) do
			arg_names:push(parameter.name)
			method_code:push('local ' .. parameter.name .. ' = ' .. 'input.' .. parameter.name)
			-- TODO: add api_description code to verify each parameter
			method_code:push('-- TODO: verify ' .. parameter.name)
		end

		-- call the method on the proxy target with the appropriate parameters
		method_code:push('return self.target:' .. name.. '(' .. table.concat(arg_names, ', ') .. ')')

		local code = table.concat(method_code, '\n')
		local proxy_method, compile_error = loadstring(code)
		if not proxy_method then
			error('error creating proxy ' .. compile_error .. '\n' .. code)
		end
		return proxy_method
	end
end)
