-- utils to create random keys
-- copyright 2014 Samuel Baird MIT Licence

local string = require('string')
local math = require('math')
local table = require('table')
local os = require('os')
local io = require('io')

local module = require('core.module')
local array = require('core.array')

return module(function (template)
	
	function template.from_file(name)
		local input = assert(io.open(name, 'r'))
		local source = input:read('*a')
		input:close()
		return template.from_string(source, name)
	end
	
	function template.from_string(template_source, name)
		-- create a function that will evaluate this template with arguments and return a string
		-- split the template into static and dynamic sections
		
		-- {{ }} sections are expressions that evalute to text
		-- {{{ }}} sections are statements that can use write() to write to the output
	
		local sections = array()
		local start = 1
		while start <= #template_source do
			local ds, de = template_source:find('%b{}', start)
			if ds then
				-- push any static content prior to the dynamic section
				if ds > start then
					sections:push({
						type = 'static',
						source = template_source:sub(start, ds - 1),
					})
				end
				
				local dynamic_section = template_source:sub(ds, de)
				
				-- triple bracketed, treat as statements
				if #dynamic_section > 6 and dynamic_section:sub(1, 3) == '{{{' and dynamic_section:sub(-3, -1) == '}}}' then
					sections:push({
						type = 'statement',
						source = dynamic_section:sub(4, -4),
					})
					
				-- double bracketed, treat as an expression
				elseif #dynamic_section > 4 and dynamic_section:sub(1, 2) == '{{' and dynamic_section:sub(-2, -1) == '}}' then
					sections:push({
						type = 'expression',
						source = dynamic_section:sub(3, -3),
					})
					
				-- single bracketed, might be embedded javascript or something
				else
					sections:push({
						type = 'static',
						source = dynamic_section,
					})
				end

				start = de + 1
			else
				-- push any remaining static content
				sections:push({
					type = 'static',
					source = template_source:sub(start),
				})
				break
			end
		end
	
		local code = array()
		-- begin with a preamble to allow read but not write to the global name table
		-- write all the input fields into this temporary global table
		code:push('local input = (...) or {}')
		code:push('setmetatable(input, { __index = _G })')
		code:push('setfenv(1, input)')
		code:push('')
		
		-- include a function that can write output for this template
		code:push('local out = {}')
		code:push('local function write(val)')
		code:push('  local s = tostring(val)')
		code:push('  if s then')
		code:push('    out[#out + 1] = s')
		code:push('  end')
		code:push('end')
		code:push('')
	
		-- build the source code of the template function
		for _, section in ipairs(sections) do
			if section.type == 'static' then
				code:push('write([[\n' .. section.source .. ']])')
				code:push('')
			elseif section.type == 'expression' then
				code:push('write(' .. section.source .. ')')
				code:push('')
			elseif section.type == 'statement' then
				code:push(section.source)
				code:push('')
			end
		end
		
		-- return the output as a combined string
		code:push('')
		code:push('return table.concat(out)')
		code = code:concat('\n')
		
		-- show any errors building the template
		local f, e = loadstring(code, name or template_source)
		if not f then
			error(e .. '\n' .. code)
		end
		return f
	end
	
end)