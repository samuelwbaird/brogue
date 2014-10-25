-- represents a normal HTTP response
-- the details of the response are built up by the various HTTP handlers
-- before being passed back to the thread with access to the original TCP/IP connectionp
--
-- copyright 2014 Samuel Baird MIT Licence

-- standard lua
local table = require('table')

-- external modules
local cjson = require('cjson')

-- core modules
local class = require('core.class')
local array = require('core.array')

return class(function (response)
	local super = response.new
	
	function response.new(request)
		local self = super()
		self.status_code = 200
		self.keep_alive = request and request.should_keep_alive or false
		self.headers = {
		}
		self.body = nil
		return self
	end
	
	function response:set_status(status_code)
		self.status_code = status_code
	end
	
	function response:set_header(header, value)
		self.headers[header] = tostring(value)
	end
	
	function response:set_body(body)
		if body then
			self.headers['Content-Length'] = tostring(#body)
		end
		self.body = body
	end
	
	function response:set_json(json)
		self:set_mimetype_from_extension('json')
		self:set_body(cjson.encode(json or {}))
	end
	
	function response:set_mimetype_from_extension(extension)
		local type = response.mimetypes[extension]
		if type then
			self.headers['Content-Type'] = type
		end
	end
	
	function response:__tostring()
		local h = array()
		
		if not self.keep_alive then
			self:set_header('Connection', 'close')
		end
		
		h:push('HTTP/1.1 ' .. tostring(self.status_code) .. ' ' .. (response.status_code_text[self.status_code] or ''))
		for field, value in pairs(self.headers) do
			h:push(field .. ': ' .. value)
		end
		
		if self.body then
			return table.concat(h, '\r\n') .. '\r\n\r\n' .. self.body
		else
			return table.concat(h, '\r\n')
		end
	end
	
	response.status_code_text = {
		[200] = 'OK',
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
	}
end)