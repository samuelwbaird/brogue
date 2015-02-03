-- create decorators around other objects
-- provide additional values, methods and properties
-- copyright 2014 Samuel Baird MIT Licence

local class = require('core.class')
local array = require('core.array')

return class(function (decorator)
	local super = decorator.new
	
	function decorator.new(properties)
		local self = super()
		self.properties = {}
		
		if properties then
			for k, v in pairs(properties) do
				self.properties[k] = {
					value = v
				}
			end
		end
		
		self.wrap_meta = {
			__index = function(wrap, property)
				local v = self.properties[property]
				if v then
					if v.value then
						return v.value
					elseif v.getter then
						return v.getter(wrap.obj, wrap, property)
					end
				end
				return wrap.obj[property]
			end,
			__newindex = function (wrap, property, value)
				local v = self.properties[property]
				if v then
					if v.setter then
						v.setter(wrap.obj, wrap, property, value)
					else
						v.value = value	
					end
				else
					wrap.obj[property] = value
				end
			end,
		}
		
		return self
	end
	
	function decorator:set_value(key, value)
		self.properties[key] = {
			value = value
		}
	end
	
	decorator.set_method = decorator.set_value

	function decorator:set_property(key, getter, setter)
		-- getter(obj, wrap, property)
		-- setter(obj, wrap, property, value)
		self.properties[key] = {
			getter = getter,
			setter = setter,
		}
	end
	
	function decorator:wrap(obj)
		local wrap = {
			obj = obj,
			decorator = self
		}
		setmetatable(wrap, self.wrap_meta)
		return wrap
	end
end)