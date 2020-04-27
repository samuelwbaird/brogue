-- utils to create random keys
-- copyright 2014 Samuel Baird MIT Licence

local string = require('string')
local math = require('math')
local table = require('table')
local os = require('os')

local module = require('core.module')

return module(function (random_key)
	math.randomseed(os.time())
	
	function random_key.printable(length, chars)
		chars = chars or '1234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'	

		local key = {}
		while #key < length do
			local index = math.random(1, #chars)
			key[#key + 1] = chars:sub(index, index)
		end
		return table.concat(key)
	end
	
	function random_key.unique_printable(unique_check, length, chars)
		while true do
			local key = random_key.printable(length, chars)
			if type(unique_check) == 'table' then
				if not unique_check[key] then
					return key
				end
			elseif unique_check(key) then
				return key
			end
		end		
	end
	
	
end)