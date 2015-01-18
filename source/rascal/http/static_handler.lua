-- a handler that can be used in the Lua code configuring HTTP workers
-- to serve static files
-- in memory caching of a set number of assets can be enabled
-- copyright 2014 Samuel Baird MIT Licence

-- standard lua
local io = require('io')
local string = require('string')

-- core modules
local class = require('core.class')
local array = require('core.array')
local cache = require('core.cache')

require('rascal.base')

return class(function (static)
	local super = static.new

	function static.new(path, index_path, cache_size)
		local self = super()
		self.path = path
		self.index_path = index_path
		if type(cache_size) == 'boolean' and cache_size == false then
			self.cache = nil
		else
			self.cache = cache(cache_size)
		end
		return self
	end
	
	function static:handle(request, context, response)
		local path = request.url_path
		-- remove leading /
		if path and path:sub(1, 1) == '/' then
			if #path > 1 then
				path = path:sub(2)
			else
				path = nil
			end
		end
		-- reject anything trying to path back with ..
		if path:find('%.%.') then
			return false
		end
		-- check that we actually have a path to work with
		if path == nil or path == '' then
			path = self.index_path
		end
		if path == nil then
			return false
		end
		-- check if the contents are cached
		local contents = self.cache and self.cache:get(path) or nil
		if not contents then
			-- check if the file exists for us to serve
			local input = io.open(self.path .. path, 'rb')
			if not input then
				return false
			end
			-- set the body from the file content
			contents = input:read('*a')
			if self.cache then
				self.cache:push(path, contents)
			end
			input:close()
		end
		if request.method == 'HEAD' then
			response:set_header('Content-Length', tostring(#contents))
		else
			response:set_body(contents)
		end
		-- TODO: if self.cache is set then set headers to control cache policy at the browser
		-- set a default mimetype from the extension if possible
		local extension = path:match('%.(.+)$')
		if extension then
			response:set_mimetype_from_extension(extension:lower())
		end
				
		return true
	end
end)