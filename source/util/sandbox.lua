-- module to help run sandboxed code
-- copyright 2016 Samuel Baird MIT Licence

local class = require('core.class')

return class(function (sandbox)
		
	function sandbox:init(available_values)
		self.globals = {}
		for k, v in pairs(available_values or {}) do
			self.globals[k] = v
		end
	end
	
	-- TODO: add module
	-- TODO: add safe standard modules
	-- TODO: allow writes / reads from sandbox global
	-- TODO: disallow loading bytecode
	
	function sandbox:execute_string(code)
		local chunk, message = loadstring(code)
		if not chunk then
			error(message)
		end
		return self:execute_fn(chunk)
	end
	
	function sandbox:execute_file(filename)
		local chunk, message = loadfile(filename)
		if not chunk then
			error(message)
		end
		return self:execute_fn(chunk)
	end
	
	function sandbox:execute_fn(chunk)
	    setfenv(chunk, self.globals)
	    local result, message = pcall(chunk)
		if not result then
			error('Error in sandbox ' .. message, 2)
		end
		return message
	end
	
end)