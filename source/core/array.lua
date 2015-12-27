-- module to give array tables some standard convenience functions
-- copyright 2014 Samuel Baird MIT Licence

local table = require("table")
local math = require("math")
local coroutine = require("coroutine")

local class = require("core.class")

local pairs, ipairs = pairs, ipairs

return class(function (array)
	
	-- capture the default constructor
	local super = array.new
	
	-- custom constructor
	function array.new(init)
		-- optionally initialise from an iterator
		if type(init) == 'function' then
			return array():collect(init)
		end
		
		local self = super()
		
		-- copy the contents of a table if supplied
		if type(init) == 'table' then
			for i, v in ipairs(init) do
				self[i] = v
			end
		end
		
		return self
	end

	-- call a function on each element
	function array:with_each(fn)
		for i, v in ipairs(self) do
			fn(v)
		end
	end
	
	-- length as a function
	function array:length()
		return #self
	end
	
	-- produce an iterator
	function array:each()
		local i = 0
		return function ()
			if i < #self then
				i = i + 1
				return self[i]
			else
				return nil
			end
		end
	end

	-- clone, shallow copy
	function array:clone()
		local out = array()
		for i, v in ipairs(self) do
			out[i] = v
		end
		return out
	end
	
	-- test for a given member
	function array:contains(member)
		for i, v in ipairs(self) do
			if v == member then
				return true
			end
		end
		return false
	end

	-- map, return a transposed array
	function array:map(fn)
		local out = array()
		for i, v in ipairs(self) do
			out[i] = fn(v)
		end
		return out
	end

	-- filter (keep/remove from predicate, return new)
	function array:filter(fn)
		local out = array()
		for _, v in ipairs(self) do
			if fn(v) then
				out[#out + 1] = v
			end
		end
		return out
	end
	
	-- update (mutate or remove each entry from function)
	function array:mutate(fn)
		local out = 0
		for i, v in ipairs(self) do
			local updated = fn(v)
			if updated then
				out = out + 1
				self[out] = updated
			end
		end
		local len = #self
		while len > out do
			self[len] = nil
			len = len - 1
		end
		return self
	end
	
	-- clear
	function array:clear()
		local len = #self
		while len > 0 do
			self[len] = nil
			len = len - 1
		end
		return self
	end
	
	function array:is_empty()
		return next(self) == nil
	end

	function array:push_back(value)
		self[#self + 1] = value
	end
	
	function array:push_front(value)
		table.insert(self, 1, value)
	end
	
	function array:remove_element(element, more_than_once)
		for i, v in ipairs(self) do
			if v == element then
				table.remove(self.actions, i)
				if not more_than_once then
					return;
				end
			end
		end
	end
	
	function array:collect(iterator_fn, state, ...)
		local vars = {...}
		local length = #self
		while true do
	        vars = { iterator_fn(state, vars[1]) }
	        if vars[1] == nil then 
				return self
			end
			length = length + 1
			self[length] = vars[1]
		end
		return self
	end

	-- return a coroutine that will iterate through all permutations of array ordering
	function array:permutations()
		return coroutine.wrap(function()
			if #self == 1 then
				coroutine.yield(self);
			else
				-- permutation is equal to an element in each position, with all permutations of the other elements before and after
				local element = self[1]
				local the_rest = self:clone()
				the_rest:remove(1)

				for sub_permutation in the_rest:permutations() do
					for insert_index = 1, #sub_permutation + 1 do
						local permutation = sub_permutation:clone()
						permutation:insert(insert_index, element)
						coroutine.yield(permutation)
					end
				end
			end
			coroutine.yield(nil)
		end)
	end
	
	function array:random_permutation()
		local out = array.new()
		local working = self:clone()
		while #working > 0 do
			local random_index = math.random(1, #working)
			out:push(working[random_index])
			working:remove(random_index)
		end
		return out
	end

	-- aliases
	array.add = array.push_back
	array.push = array.push_back
	array.size = array.length
	
	array.concat = table.concat
	array.insert = table.insert
	array.remove = table.remove
	array.maxn = table.maxn
	array.sort = table.sort

	function array:__tostring()
		local strings = {}
	    for i, v in ipairs(self) do
			strings[i] = tostring(v)
		end
		return '[' .. table.concat(strings, ', ') .. ']'
	end
	
end)