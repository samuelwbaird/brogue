local string = require('string')
local math = require('math')
local table = require('table')
local os = require('os')

local module = require('core.module')

return module(function (random_key)
	math.randomseed(os.time())
	
	
	function random_key.printable(length)
		local chars = '1234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'	

		local key = {}
		while #key < length do
			local index = math.random(1, #chars)
			key[#key + 1] = chars:sub(index, index)
		end
		return table.concat(key)
	end
	
end)