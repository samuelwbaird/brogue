-- represents an HTTP request
-- parses itself from the raw text input
--
-- copyright 2014 Samuel Baird MIT Licence

local os = require('os')

-- external modules
local cjson = require('cjson')
local cmsgpack = require('cmsgpack')

-- core modules
local class = require('core.class')
local array = require('core.array')


return class(function (request)
	
	function request:init(request_string)
		self.headers = {}
		
		self.time = os.time()
		
		-- set a timeout after which long pollling should consider this connection dead
		-- a short timeout means less chance of sending data to a recycled connection address
		-- a too short timeout means the browser waiting for data we don't send that we could have
		-- it seems mobile safari defaults to 60s but we may need to adjust this based on the referral string
		self.timeout = 30
		
		local header = nil
		local index_header = request_string:find('\r\n\r\n')
		if index_header then
			header = request_string:sub(1, index_header + 2)
			if index_header < #request_string - 4 then
				self.body = request_string:sub(index_header + 4)
			end
		else
			header = request_string
		end
		
		if header then
			-- get method, headers, url
			local first_line = nil
			for line in header:gmatch('(.-)\r\n') do
				if first_line then
					local field, value = line:match('(.-):%s(.*)')
					self.headers[field] = value
				else
					first_line = line
				end
			end
			if first_line then
				self.method, self.url, self.http = first_line:match('([^%s]*)%s*([^%s]*)%s*([^%s]*)')
			end
			-- should keep alive
			self.should_keep_alive = (self.http == 'HTTP/1.1' or self.headers['Connection'] == 'keep-alive')
		end
		
		if self.url then
			-- url_path, url_query, url_fragement
			self.url_path, self.url_query, self.url_fragment = request.parse_path_query_fragment(self.url)
			-- url query vars
			if self.url_query then
				self.url_vars = request.query_vars(self.url_query)
			end
		end
	end
	
	function request:reset()
		self.url_path = self.original_url_path or self.url_path
	end
	
	-- detect JSON, msgpack, TODO: URL vars, form vars, detect from content without header
	function request:input()
		local content_type = self.headers['Content-Type']
		if content_type then
			if content_type:find('application/x-msgpack') or content_type:find('application/msgpack') then
				return self:msgpack()
			end
		end

		-- assume JSON by default
		return self:json()
	end
	
	function request:json()
		return self.body and cjson.decode(self.body) or {}
	end
	
	function request:msgpack()
		return self.body and cmsgpack.unpack(self.body) or {}
	end
	
	function request:rewrite_url_path(new_url_path)
		if not self.original_url_path then
			self.original_url_path = self.url_path
		end
		self.url_path = new_url_path or ''
	end
	
	function request.url_decode(str)
		str = string.gsub (str, '+', ' ')
		str = string.gsub (str, '%%(%x%x)',
			function(h) return string.char(tonumber(h,16))
		end)
		str = string.gsub (str, '\r\n', '\n')
		return str
	end
	
	function request.query_vars(query)
		local vars = {}
		for slug in query:gmatch('([^%&]+)') do
			local field, value = slug:match('(.-)=(.*)')
			vars[request.url_decode(field)] = request.url_decode(value)
		end
		return vars
	end
	
	function request.parse_path_query_fragment(uri)
	    local path, query, fragment, off
	    -- parse path
	    path, off = uri:match('([^?]*)()')
	    -- parse query
	    if uri:sub(off, off) == '?' then
	        query, off = uri:match('([^#]*)()', off + 1)
	    end
	    -- parse fragment
	    if uri:sub(off, off) == '#' then
	        fragment = uri:sub(off + 1)
	        off = #uri
	    end
	    return path or '/', query, fragment
	end
	
end)