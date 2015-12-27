-- runs a text based lua shell with proxy functions
-- connected to rascal services
-- enter valid lua code for a response
-- enter an empty line for a list of proxy commands available
-- copyright 2014 Samuel Baird MIT Licence

local math = require('math')
local os = require('os')
local io = require('io')
local table = require('table')

local class = require('core.class')
local array = require('core.array')

local rascal = require('rascal.core')

function pretty(value)
	if type(value) == 'string' then
		return '"' .. value .. '"'
	elseif type(value) == 'number' or type(value) == 'string' or type(value) == 'boolean' or type(value) == 'nil' then
		return tostring(value)
	elseif type(value) == 'function' then
		return 'function'
	elseif #value > 0 then
		local temp = {}
		for k, v in ipairs(value) do
			temp[k] = pretty(v)
		end
		return '{ ' .. table.concat(temp, ', ') .. ' }'
	else
		local temp = {}
		for k, v in pairs(value) do
			temp[#temp + 1] = k .. ' = ' .. pretty(v)
		end
		return '{ ' .. table.concat(temp, ', ') .. ' }'
	end
end

return class(function (shell)

	function shell:init(services)
		self.proxies = array()
		for _, service in ipairs(services) do
			local proxy = rascal.registry:connect(service)
			self.proxies:push(proxy)
			for method_name, method_function in pairs(proxy) do
				if type(method_function) == 'function' then
					-- push each command to the global namespace
					_G[method_name] = function (...)
						return proxy[method_name](proxy, ...)
					end
				end
			end
		end
	end	
	
	function shell:loop()
		self:display_commands()
		while true do
			io.write('shell> ')
			io.flush()
			
			local input = io.read()
			if not input then
				break
			elseif input == '' then
				self:display_commands()
			elseif input == 'quit' or input == 'exit' then
				break
			else
				local command, error = loadstring('return ' .. input)
				if command then
					local success, result = pcall(command)
					if (success) then
						self:out(pretty(result))
						--self:out(tostring(result))
					else
						self:out('runtime error ' .. result)
					end
				else
					self:out('command error ' .. error)
				end
			end
		end
	end
	
	function shell:display_commands()
		self:out('services')
		for _, proxy in ipairs(self.proxies) do
			for name, description in pairs(proxy.api_description) do
				self:out(name .. '\t' .. description)
			end
		end
	end
	
	function shell:out(line)
		print('shell: ' .. line)
	end
	
end)