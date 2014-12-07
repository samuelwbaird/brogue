-- a fixed number of worker threads are used to service the HTTP requests
-- workers are configured using a block of Lua code, that sets up
-- a chain of handlers
-- the worker module contains the text of a number of utility handlers
-- that are available by default to the supplied code
-- the worker also has basic support to hold a number of deferred requests
-- that can be signalled for reply when appropriate, to treat otherwise basic HTTP
-- requests into long polled requests
--
-- copyright 2014 Samuel Baird MIT Licence

local coroutine = require('coroutine')
local os = require('os')

-- core modules
local class = require('core.class')
local mru = require('core.mru')

-- normally runs as a rascal thread
local rascal = require('rascal.core')
local http_request = require('rascal.http.request')
local http_response = require('rascal.http.response')

return class(function (http_worker)
	local super = http_worker.new
	
	function http_worker.new(configuration, worker_request_address, push_reply_address, worker_identity)
		local self = super()
		self.deferred_connections = mru(1024)
		
		-- print('starting worker ' .. worker_identity)
		local handler_script = http_worker.create_handler(configuration)
		-- execute to create the chain and keep it
		self.handler = handler_script(self)
		
		-- receive requests from the router
		self.request_from_router = ctx:socket(zmq.REQ)
		self.request_from_router:set_identity(worker_identity)
		self.request_from_router:connect(worker_request_address)
		
		-- push them back
		self.push_to_router = ctx:socket(zmq.PUSH)
		self.push_to_router:connect(push_reply_address)
		
		-- tell the worker we're ready
		self.request_from_router:send('ready')
		loop:add_socket(self.request_from_router, function (request_from_router)
			-- wait to be given some work
			local input = request_from_router:recv_all()
			if input == nil then
				return
			end
			
			local address, body = input[1], input[3]
			if body == nil then
				return
			end
			
			local request = http_request(body)
			local response = http_response(request)
			local context = {
				address = address,
				http_worker = self
			}
			
			self:handle_request(request, context, response)
		
			-- tell the worker we're ready for more work
			request_from_router:send('ready')
		end)
		
		return self
	end

	function http_worker:handle_request(request, context, response)
		-- rascal.log('verbose', request.method .. ' ' .. (request.url_path or '') .. ' ' .. (request.url_query or ''))

		-- run request, context, response through the handler configuration
		local completed, result = pcall(self.handler, request, context, response)		
		if completed then
			-- has this been deferred as part of long polling
			if context.deferred then
				return;
			end
			-- did we run to the end of the handler with out it being handled
			if not result then
				rascal.log('error', '404 ' .. (request.url_path or ''))
				response:set_status(404)
			end
		else
			-- error during processing
			rascal.log('error', '500 ' .. (request.url_path or '') .. ' ' .. result)
			response:set_status(500)
			response:set_body(result)
		end
		
		-- send handle + response
		local output = tostring(response)
		-- rascal.log('verbose', output)
		
		self.push_to_router:send_all({
			context.address,
			output,
		})

		-- send handle + '' to close (or maybe don't to support long poll)
		if response.keep_alive and response.body then
			-- send a message to terminate this connection later
		else
			self.push_to_router:send_all({
				context.address,
				'',
			})
		end
	end
	
	-- support long polling, defer response until signalled
	function http_worker:defer(signal, request, context, response)
		if not context.deferred then
			context.deferred = true
			context.defer_count = 1 + (context.defer_count or 0)
			self.deferred_connections:push(signal, {
				request = request,
				context = context,
				response = response,
			})
		end
	end

	-- signal to retry handling any relevant long connections
	function http_worker:signal(signal)
		local connection = self.deferred_connections:pull(signal)
		if not connection then
			return
		end
		-- check its not too stale
		if connection.request.time + connection.request.timeout < os.time() then
			return
		end
		connection.context.deferred = false
		connection.request:reset()
		self:handle_request(connection.request, connection.context, connection.response)
	end

	-- creating scripted handlers

	function http_worker.create_handler(configuration)
		local preamble =  
[=====================[
local http_worker = ...

local function use_handler(handler, request, context, response)
	-- apply either a handler or an array of handlers

	if type(handler) == 'function' then
		-- if its a function assume its ready to go
		return handler(request, context, response)
	elseif type(handler) == 'table' then
		-- try each one until one handler accepts the request
		for _, h in ipairs(handler) do
			local result = use_handler(h, request, context, response)
			if result then
				return result
			end
		end
	end
	return false
end

local function prefix(prefix_string, handler)
	-- create a handler that matches a prefix, removes it from the path and continues
	local prefix_handler = require('rascal.http.prefix_handler') (prefix_string)

	-- recursively handle if prefix matches
	return function (request, context, response)
		if prefix_handler:handle(request, context, response) then
			return use_handler(handler, request, context, response)
		end
	end
end

local function match(match_string, handler)
	-- create a handler that matches a lua string pattern, returns the capture
	local match_handler = require('rascal.http.match_handler') (match_string)

	-- recursively handle if prefix matches
	return function (request, context, response)
		if match_handler:handle(request, context, response) then
			return use_handler(handler, request, context, response)
		end
	end
end

local function equal(url_path, handler)
	-- create a handler that matches a strict equality
	local equal_handler = require('rascal.http.equal_handler') (url_path)

	-- recursively handle if prefix matches
	return function (request, context, response)
		if equal_handler:handle(request, context, response) then
			return use_handler(handler, request, context, response)
		end
	end
end

local function rewrite(rewriter, handler)
	return function (request, context, response)
		if type(rewriter) == 'string' then
			request:rewrite_url_path(rewriter)
		elseif type(rewriter) == 'function' then
			rewriter(request)
		end
		return use_handler(handler, request, context, response)
	end
end

local function static(path, index_path, cache_size)
	-- create an instance of the static handling class
	local static_handler = require('rascal.http.static_handler') (path, index_path, cache_size)

	-- create a handler that serves static content
	return function (request, context, response)
		return static_handler:handle(request, context, response)
	end
end

local function session(handler)
	-- create a handler that wraps session cookie tracking
	
	return function (request, context, response)
		
		-- then proxy through the inner handler
		return use_handler(handler, request, context, response)
	end
end

local function redirect(path)
	return function (request, context, response)
		response:set_status(303)
		response:set_header('Location', path)
		return true
	end
	
end

-- custom handler
local function handler(handler_class_name, args)
	local handle_instance = require(handler_class_name) (unpack(args))

	return function (request, context, response)
		return handle_instance:handle(request, context, response)
	end
end

-- custom chain
local function chain(chain_class_name, args, handler)
	local chain_instance = require(chain_class_name) (unpack(args))

	return function (request, context, response)
		if chain_instance:handle(request, context, response) then
			return use_handler(handler, request, context, response)
		end
	end
end
	
local user_supplied_handler = {
]=====================]

		-- could strip leading tabs more nicely
		local script = preamble .. '\n\n' .. configuration .. 
[=====================[
}
return function(request, context, response)
	return use_handler(user_supplied_handler, request, context, response)
end
]=====================]
		
		local handler, compile_error = loadstring(script)
		if not handler then
			error('error creating handler ' .. compile_error .. '\n' .. script)
		end
		return handler
	end


end)