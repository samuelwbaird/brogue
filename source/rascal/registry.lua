require('rascal.base')

-- lua classs
local io = require('io')
local os = require('os')

-- external classs
local cmsgpack = require('cmsgpack')

-- core classs
local class = require('core.class')
local array = require('core.array')

local proxy_client = require('rascal.proxy.client')
local proxy_server = require('rascal.proxy.server')
local proxy_aggregate = require('rascal.proxy.aggregate')

return class(function (registry)
	
	registry.push_api_description = {
		set = 'key:string, value:*',
		publish = 'service_id:string, channel:string, socket_type:string, api_description:object',
	}
	
	registry.req_api_description = {
		get = 'key:string -> *',
		wait = 'key:string -> *',
	}
	
	function registry.client(push_channel, req_channel)
		push_channel = push_channel or 'inproc://rascal.registry.push'
		req_channel = req_channel or 'inproc://rascal.registry.req'
		
		local push_client = proxy_client(push_channel, zmq.PUSH, registry.push_api_description)
		local req_client = proxy_client(req_channel, zmq.REQ, registry.req_api_description)
		
		-- hook up convenience connect function
		function req_client:connect(key)
			local service_details = self:wait('publish.service.' .. key)
			assert(service_details, 'could not connect to ' .. key)
			if service_details then
				-- return a proxy for the given service
				return proxy_client(service_details.channel, service_details.socket_type, service_details.api_description)
			end
		end
		
		function req_client:connect_sub(key, target)
			local service_details = self:wait('publish.service.' .. key)
			assert(service_details, 'could not connect to ' .. key)
			if service_details then
				-- return a non published proxy server to respond to incoming PUBs
				return proxy_server(target, service_details.api_description, service_details.channel, service_details.socket_type)
			end
		end
		
		return proxy_aggregate({ push_client, req_client })
	end
	
	local super = registry.new
	
	function registry.new()
		local self = super()
		
		self.registry_values = {}
		self.key_clients = {}
		self.router = nil

		return self
	end
	
	function registry:queue_for_key(key)
		local a = self.key_clients[key]
		if not a then
			a = array()
			self.key_clients[key] = a
		end
		return a
	end

	function registry:bind(pull_channel, rep_channel)
		pull_channel = pull_channel or 'inproc://rascal.registry.push'
		rep_channel = rep_channel or 'inproc://rascal.registry.req'
		
		proxy_server(self, registry.push_api_description, pull_channel, zmq.PULL)
		self.router = proxy_server(self, registry.req_api_description, rep_channel, zmq.ROUTER)
	end
	
	-- push functions
	
	function registry:set(key, value)
		self.registry_values[key] = value
		-- are then any queued clients waiting for this key
		local a = self.key_clients[key]
		if a then
			self.key_clients[key] = nil
			a:with_each(function (routing)
				self.router:route_response(routing, value)
			end)
		end
	end
	
	function registry:publish(service_id, channel, socket_type, api_description)
		self:set('publish.service.' .. service_id, {
			service_id = service_id,
			channel = channel,
			socket_type = socket_type,
			api_description = api_description,
		})
	end
		
	-- router functions
	
	function registry:get(key)
		local value = self.registry_values[key]
		if value then
			self.router:route_response(self.router.routing, value)
		else
			self.router:route_response(self.router.routing, nil)
		end
	end
	
	function registry:wait(key)
		local value = self.registry_values[key]
		if value then
			self.router:route_response(self.router.routing, value)
		else
			self:queue_for_key(key):push(self.router.routing)
		end
	end
end)