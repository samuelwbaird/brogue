-- uses a 0MQ router in raw mode to provide a basic HTTP server
-- basic collection of the HTTP request is handled at this level
-- then the request is handed off to a queue or worker threads
-- for proper parsing and handling
-- the TCP/IP connection is held open for the worker to send responses
-- back, via this thread
--
-- copyright 2014 Samuel Baird MIT Licence

-- core modules
local module = require('core.module')
local queue = require('core.queue')

-- normally runs as a rascal thread
local cache = require('core.cache')
local rascal = require('rascal.core')

return module(function (http_server)

	function http_server.bind(address, worker_request_address, push_reply_address)
		rascal.log('http', 'serving http on ' .. address)
		
		-- prepare the sockets
		
		local external_router = ctx:socket(zmq.ROUTER)
		external_router = ctx:socket(zmq.ROUTER)
		external_router:set_router_raw(1)
		external_router:bind(address)
		
		local internal_router = ctx:socket(zmq.ROUTER)
		internal_router:bind(worker_request_address)
		
		local pull_from_workers = ctx:socket(zmq.PULL)
		pull_from_workers:bind(push_reply_address)
		
		-- lru worker queue
		
		local worker_queue = queue()
		local input_queue = queue()
		
		-- buffer incomplete input
		
		local input_buffer = cache(1024 * 16)	-- this will need to expire or is a DOS leak
		
		-- prepare the loop

		loop:add_socket(external_router, function (external_router)
			-- recieve handle + input
			local input = external_router:recv_all()
			local external_address, body = input[1], input[2]
						
			local buffer = input_buffer:peek(external_address)
			if buffer then
				body = buffer.request .. body
			end
			
			if http_server.buffer_request(input_buffer, external_address, body) then
				return
			else
				input_buffer:clear(external_address)
			end
			
			local worker_address = worker_queue:pop()
			if worker_address then
				-- print('input send queued worker ' .. worker_address)
				internal_router:send_all({
					worker_address,
					'',
					external_address,
					'',
					body,
				})
			else
				-- print('input queued')
				input_queue:push({
					external_address,
					body
				})
			end
		end)
		
		loop:add_socket(internal_router, function (internal_router)
			local ready = internal_router:recv_all()
			local worker_address = ready[1]
			
			-- print('worker ready ' .. worker_address)
			
			local input = input_queue:pop()
			if input then
				-- send direct to the worker
				local external_address, body = input[1], input[2]
				-- print('worker send queued input')
				internal_router:send_all({
					worker_address,
					'',
					external_address,
					'',
					body,
				})
			else
				-- queue the worker address
				-- print('worker waiting ' .. worker_address)
				worker_queue:push(worker_address)
			end
		end)
		
		loop:add_socket(pull_from_workers, function (pull)
			-- echo out handle + input
			local worker_response = pull:recv_all()
			local external_address, response = worker_response[1], worker_response[2]
			-- print('worker response')
			external_router:send_all({
				external_address,
				response,
			})
		end)
		
	end
	
	function http_server.buffer_request(input_buffer, external_address, request)
		-- find content length
		local content_length = tonumber(request:match('Content%-Length:%s*(%d+)'))
		local _, header_length = request:find('\r\n\r\n')
		if header_length and not content_length then
			content_length = 0
		end
		
		-- max body length
		if content_length and content_length > 1024 * 1024 then
			input_buffer:clear(external_address)
			return true
		end
		
		-- -- missing content or header after a certain size
		if (not header_length) and (#request > 1024 * 32) then
			input_buffer:clear(external_address)
			return true
		end

		-- request is complete and ready to go
		if header_length and content_length and #request >= (header_length + content_length) then
			return false
		end
		
		local buffer_settings = {
			content_length = content_length,
			header_length = header_length,
			request = request,
		}
		input_buffer:push(external_address, buffer_settings)
		return true
	end

end)