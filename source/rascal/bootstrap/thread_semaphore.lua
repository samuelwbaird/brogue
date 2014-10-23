require('rascal.base')

-- lua modules

-- core modules
local class = require('core.class')


return class(function (thread_semaphore)
	local super = thread_semaphore.new
	
	function thread_semaphore.new(channel)
		local self = super()
		self.channel = channel
		self.ids = {}
		self.pull_socket = ctx:socket(zmq.PULL)
		self.pull_socket:bind(channel)		
		self.loop = zloop.new()
		self.loop:add_socket(self.pull_socket, function (pull_socket)
			local input = pull_socket:recv_all()
			for _, value in ipairs(input) do
				self.ids[value] = value
			end
		end)
		return self
	end
	
	function thread_semaphore:wait(id, clear_first)
		if clear_first then
			self.ids[id] = nil
		end
		while not self.ids[id] do
			self.loop:sleep_ex(5)
		end
	end
	
	function thread_semaphore.signal(channel, id)
		local push_socket = ctx:socket(zmq.PUSH)
		push_socket:connect(channel)		
		push_socket:send(id)
		push_socket:close()
	end

end)