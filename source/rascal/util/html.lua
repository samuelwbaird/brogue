-- utils to build HTML strings
-- copyright 2014 Samuel Baird MIT Licence

local class = require('core.class')
local array = require('core.array')

local dom_types = {}

local function init_function(baseclass)
	local super = baseclass.new
	return function(...)
		local self = super()
		self.children = array()
		self.attributes = {}
		self:init(...)
		return self
	end
end

-- base level class for any DOM node
local node = class(function (node)
	node.new = init_function(node)
	
	function node:init(name, ...)
		self.name = name
	end
	
	function node:add(child)
		child.parent = self
		self.children:add(child)
	end
	
	function node:__tostring()
		local line_break = (not self:has_text(2)) and #self.children > 0
		local closed = not self.text and #self.children == 0
		
		local out = array()

		-- opening tag
		if self.name then
			out:push('<' .. self.name)
			for k, v in pairs(self.attributes) do
				out:push(' ' .. k .. '="' .. tostring(v) .. '"')
			end
			if closed then
				out:push('/>')
			else
				out:push('>')
			end
		end
		if line_break then
			out:push('\n')
		end
		if not closed then
			-- add text property if present
			if self.text then
				out:push(self.text)
			end
			-- recurse children
			if self.children then
				for _, child in ipairs(self.children) do
					if type(child) == 'string' then
						out:push(child)
					elseif type(child) == 'number' or type(child) == 'boolean' then
						out:push(tostring(child))
					else
						out:push(tostring(child))
					end
				end
			end
			-- closing tag if needed
			if self.name then
				out:push('</' .. self.name .. '>')
			end
		end
		if self.name then
			out:push('\n')
		end
		return out:concat()
	end
	
	function node:has_text(depth)
		if self.text then
			return true
		end
		for _, child in ipairs(self.children) do
			if type(child) == 'string' then
				return true
			else
				if depth and depth > 1 and child:has_text(depth - 1) then
					return true
				end
			end
		end
		return false
	end
	
end)

-- create default types
for _, nodename in ipairs({ 'tag', 'title', 'head', 'body', 'div', 'span', 'p', 'br', 'hr', 'script', 'img', 'html', 'table', 'tr', 'td', 'th', 'h1', 'h2', 'h3', 'h4', 'h5' }) do
	dom_types[nodename] = class(function (nodetype)
		nodetype.new = init_function(nodetype)
		nodetype:mixin(node)
		
		function nodetype:init(a1, a2)
			self.name = nodename
			
			if type(a1) == 'number' or type(a1) == 'boolean' then
				a1 = tostring(a1)
			end
			if type(a2) == 'number' or type(a2) == 'boolean' then
				a2 = tostring(a2)
			end
			
			if type(a1) == 'string' then
				self.text = a1
			elseif type(a2) == 'string' then
				self.text = a2
			end
			if type(a1) == 'table' then
				for k, v in pairs(a1) do
					self.attributes[k] = v
				end
			elseif type(a2) == 'table' then
				for k, v in pairs(a2) do
					self.attributes[k] = v
				end
			end
		end
	end)
end

-- HTML document
dom_types.document = dom_types.html

-- make any node type findable or addable from any other node type
for type, class in pairs(dom_types) do
	for other_type, other_class in pairs(dom_types) do
		
		-- find a given type or add it if required
		class[other_type] = function (parent)
			for _, child in ipairs(parent.children) do
				if getmetatable(child) == other_class then
					return child
				end
			end
			return parent['add_' .. other_type](parent)
		end
		
		-- append a new one and return it
		class['add_' .. other_type] = function (parent, ...)
			local new_child = other_class.new(...)
			parent:add(new_child)
			return new_child
		end
	end
end

-- return a package of all classes, defaulting to constructing a new document
return class.package(dom_types, dom_types.html.new)
