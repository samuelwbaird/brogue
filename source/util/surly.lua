-- basic serialisation support for simple lua tables only
-- intended for use instead of JSON or msgpack in when communicating
-- between different lua environments
-- copyright 2020 Samuel Baird MIT Licence

local module = require('core.module')
local sandbox = require('util.sandbox')

return module(function (surly)
		
	local function encode_value(value, output)
		local t = type(value)
		if t == 'string' then
			output[#output + 1] = string.format('%q', value)
		elseif t == 'table' then
			output[#output + 1] = '{'
			if #value > 0 then
				for i, v in ipairs(value) do
					if i > 1 then
						output[#output + 1] = ','
					end
					encode_value(v, output)
				end
			else
				local first = true
				for k, v in pairs(value) do
					if first then
						first = false
					else
						output[#output + 1] = ','
					end
					if type(k) == 'string' then
						output[#output + 1] = '['
						encode_value(k, output)
						output[#output + 1] = ']='
						encode_value(v, output)
					else
						encode_value(k, output)
						output[#output + 1] = '='
						encode_value(v, output)
					end
				end
			end
			output[#output + 1] = '}'
		elseif t == 'boolean' or t == 'number' then
			output[#output + 1] = to_string(value)
		elseif value == nil then
			output[#output + 1] = 'nil'
		else
			error('surly unsupport type ' .. t)
		end
	end
		
	function surly.serialise(value)
		local output = { 'return ' }
		encode_value(value, output)
		return table.concat(output, '')
	end
	
	function surly.parse(string)
		-- use the lua parser to interpret the information
		-- running in an empty sandbox
		local env = sandbox()
		return env:execute_string(string)
	end

end)