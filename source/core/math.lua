-- required globals & packages
local lua_math = require('math')
local module = require('core.module')

-- extend the built in math module
return module(function (math)
	-- inherit lua math package
	math:mixin(lua_math)

	-- clamp, lerp, round, roundBy, sigfig
	function math.clamp(val, min, max)
		if val < min then
			return min
		elseif val > max then
			return max
		else
			return val
		end
	end
	
	function math.lerp(val, to_val, ratio)
		return (val * (1.0 - ratio)) + (to_val * ratio)
	end
end)