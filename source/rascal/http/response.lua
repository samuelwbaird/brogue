-- represents a normal HTTP response
-- the details of the response are built up by the various HTTP handlers
-- before being passed back to the thread with access to the original TCP/IP connectionp
--
-- copyright 2014 Samuel Baird MIT Licence

-- standard lua
local table = require('table')

-- external modules
local cjson = require('cjson')
local cmsgpack = require('cmsgpack')

-- core modules
local class = require('core.class')
local array = require('core.array')

return class(function (response)
	
	function response:init(request)
		self.status_code = 200
		self.keep_alive = request and request.should_keep_alive or false
		self.accept_type = request.headers['accept-type']
		self.headers = {}
		self.body = nil
	end
	
	function response:set_status(status_code)
		self.status_code = status_code
	end
	
	function response:set_header(header, value)
		header = header:lower()
		value = tostring(value)
		for _, header_entry in ipairs(self.headers) do
			if header_entry.header == header then
				header_entry.value = value
				return
			end
		end
		self.headers[#self.headers + 1] = {
			header = header,
			value = value
		}
	end
	
	function response:add_header(header, value)
		header = header:lower()
		value = tostring(value)
		self.headers[#self.headers + 1] = {
			header = header,
			value = value
		}
	end
	
	function response:get_header(header)
		header = header:lower()
		for _, header_entry in ipairs(self.headers) do
			if header_entry.header == header then
				return header_entry.value
			end
		end
	end
	
	function response:set_body(body)
		if body then
			body = tostring(body)
			self:set_header('content-length', #body)
			self.body = body
		end
	end
	
	-- set JSON or msgpack output based on accept type
	function response:set_output(data)
		if self.accept_type == 'application/msgpack' or self.accept_type == 'application/x-msgpack' then
			self:set_msgpack(data)
		else
			self:set_json(data)
		end
	end
	
	function response:set_json(json)
		self:set_mimetype_from_extension('json')
		self:set_body(cjson.encode(json or {}))
	end
	
	function response:set_msgpack(data)
		self:set_mimetype_from_extension('msgpack')
		self:set_body(cmsgpack.pack(data))
	end
	
	function response:set_mimetype_from_extension(extension)
		local type = response.mimetypes[extension]
		if type then
			self:set_header('content-type', type)
		end
	end
	
	function response:__tostring()
		local h = array()
		
		if not self.keep_alive then
			self:set_header('Connection', 'close')
		end
		
		h:push('HTTP/1.1 ' .. tostring(self.status_code) .. ' ' .. (response.status_code_text[self.status_code] or ''))
		for _, header_entry in pairs(self.headers) do
			h:push(header_entry.header .. ': ' .. header_entry.value)
		end

		return table.concat(h, '\r\n') .. '\r\n\r\n' .. (self.body or '')
	end
	
	response.status_code_text = {
		[200] = 'OK',
		[401] = 'Unauthorised',
		[403] = 'Forbidden',
		[404] = 'Not Found',
		[500] = 'Internal Server Error',
	}
	
	response.mimetypes = {
		['a'] = 'application/octet-stream',
		['aif'] = 'audio/aiff',
		['aiff'] = 'audio/x-aiff',
		['au'] = 'audio/basic',
		['bin'] = 'application/octet-stream',
		['bmp'] = 'image/bmp',
		['bz2'] = 'application/x-bzip2',
		['css'] = 'text/css',
		['gz'] = 'application/x-compressed',
		['gzip'] = 'application/x-gzip',
		['htm'] = 'text/html',
		['html'] = 'text/html',
		['htmls'] = 'text/html',
		['ico'] = 'image/x-icon',
		['jpeg'] = 'image/jpeg',
		['jpg'] = 'image/jpeg',
		['jps'] = 'image/x-jps',
		['js'] = 'application/x-javascript',
		['json'] = 'application/json',
		['png'] = 'image/png',
		['rtf'] = 'application/rtf',
		['shtml'] = 'text/html',
		['shtml'] = 'text/x-server-parsed-html',
		['tar'] = 'application/x-tar',
		['text'] = 'text/plain',
		['tgz'] = 'application/gnutar',
		['xml'] = 'application/xml',
		['zip'] = 'application/zip',
		['msgpack'] = 'application/x-msgpack',
	}
end)