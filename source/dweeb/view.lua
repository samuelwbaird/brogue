-- define a view for a model object
-- there are all sorts of highly typical and fundamental issues with
-- sharing objects across process boundaries
-- references vs values, snapshot vs handle, recursion
-- in short consistency vs completeness and the whole godel thing
-- philosophy aside a view is a way to configure a flattened representation
-- of an object to be produced when required
-- this it not a view in the html sense, just in the sense of getting objects across boundaries
-- copyright 2014 Samuel Baird MIT Licence

-- TODO: there may be scope to have a form of packing that can preserve referential
-- integrity at least within any view produced
-- TODO: map a metable to another view (objs with that metatable will be mapped with that view)


local class = require('core.class')
local array = require('core.array')
local cache = require('core.cache')

return class(function (view)
	
	function view:init(...)
		self.mappings = array()
		self:add_definitions(...)
	end
	
	-- add definitions
	-- an array of fields
	-- a dictionary of name => function
	function view:add_definitions(definitions, ...)
		if not definitions then
			return
		end
		
		if type(definitions) == 'string' then
			self:add_definition(definitions, definitions)
		elseif type(definitions) == 'table' then
			if #definitions > 0 then
				for _, definition in ipairs(definitions) do
					self:add_definition(definition, definition)
				end
			else
				for name, source in ipairs(definitions) do
					self:add_definition(name, source)
				end
			end
		else
			error('unknown view definition')
		end

		-- recurse remaining definitions
		view:add_definitions(...)
		return self
	end
	
	function view:add_definition(name, source)
		self.mappings:push({ name, source })
		return self		
	end
	
	function view:externalise(obj, top_level_view) -- reference_stack
		top_level_view = top_level_view or self
		local out = {}
		for _, mapping in ipairs(self.mappings) do
			local name, source = mapping[1], mapping[2]
			-- convert from source to value
			local value
			if type(source) == 'string' then
				-- allow dot paths in name and colon method calls? eg. location:externalise
				value = obj[source]
			elseif type(source) == 'function' then
				value = source(obj)
			end
			out[name] = value
		end
		return out
	end

end)