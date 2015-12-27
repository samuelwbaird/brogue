-- a shared logging endpoint for rascal
-- can be configured to log to console or file
-- logging is pushed via a 0MQ push/pull channel and serialised in this thread
-- without blocking the client thread
-- copyright 2014 Samuel Baird MIT Licence

require('rascal.base')

-- lua modules
local io = require('io')
local os = require('os')
local cmsgpack = require('cmsgpack')

-- core modules
local class = require('core.class')
local proxy_client = require('rascal.proxy.client')
local proxy_server = require('rascal.proxy.server')

return class(function (log)
	
	log.api_description = {
		log = 'type:string, text:string:optional',
		log_to_console = 'enable:boolean',
		log_to_file = 'filename:string|boolean',
		filter = 'types:array'
	}
	
	function log.client(push_channel)
		push_channel = push_channel or 'inproc://log'
		return proxy_client(push_channel, zmq.PUSH, log.api_description)
	end
	
	function log:init()
		self.console = true
		self.file = nil
	end

	function log:log_to_console(enable)
		self.console = enable
	end
	
	function log:log_to_file(filename)
		if self.file then
			self.file:close()
		end
		self.file = filename and assert(io.open(filename, 'a'), 'cannot log to ' .. filename)
	end

	function log:log(type, text)
		if type and not text then
	 		text, type = type, 'message'
	 	end
	
		local output = 
			os.date('!%F %T UTC ')  ..
			(type or '') .. ' : ' ..
			(text or '') .. '\n'
			
		if self.file then
			self.file:write(output)
			self.file:flush()
		end
		if self.console then
			io.write(output)
			io.flush()
		end
	end

	function log:bind(pull_channel)
		pull_channel = pull_channel or 'inproc://log'
		proxy_server(self, log.api_description, pull_channel, zmq.PULL)
	end

end)