-- handles http requests related to the slash service
-- push injest of logs, long poll read of APIs and cached static content

local class = require('core.class')
local array = require('core.array')
local cache = require('core.cache')

local rascal = require('rascal.core')
local template = require('rascal.util.template')
local static_handler = require('rascal.http.static_handler')

return class(function (slash_http_handler)

	function slash_http_handler:init(static_path, cache_seconds, base_url)
		self.static_path = static_path
		self.index_template = template.from_file(static_path .. 'index.html')({
			base_url = base_url,
		})
		
		-- cache static entries
		self.cache = cache()
		self.cache_seconds = cache_seconds
		
		-- connect to the session server
		self.slash_service_request = rascal.registry:connect('slash_service.request')
		self.slash_service_push = rascal.registry:connect('slash_service.push')
		rascal.registry:connect_sub('slash_service.publish', self)
	end
	
	function slash_http_handler:signal(key)
		-- retry relevant long polled queries
		worker:signal(key)
	end
	
	function slash_http_handler:handle(request, context, response)
		local path = request.url_path
		
		-- handle api calls
		if path:sub(1, 4) == 'api/' then
			-- break out the name of the world from the URL
			local prefix, method, app_id, device_id, extra = unpack(request:path_slugs())
			if method == 'apps' or method == 'devices' or method == 'logs' or method == 'push' then
				local success, api_result = pcall(self['api_' .. method], self, app_id, device_id, extra, request, context, response)
				if context.deferred then
					-- do nothing, this query will need to re-run later
				elseif success then
					response:set_status(200)
					response:set_output(api_result)
					return true
				else
					log(path .. ', error during api call, ' .. tostring(api_result) or '')
					response:set_status(400)
					return true
				end
			else
				response:set_status(404)
				return true
			end
		end
		
		if path == '' then
			response:set_body(self.index_template)
			return true
		end
		
		-- otherwise see if it can be served as static content
		return self:handle_cached_static_content(path, request, context, response)
	end
	
	function slash_http_handler:api_apps()
		return self.slash_service_request:read_apps()
	end
	
	function slash_http_handler:api_devices(app_id)
		return self.slash_service_request:read_devices(app_id)
	end
	
	function slash_http_handler:api_logs(app_id, device_id, extra, request, context, response)
		-- read last scene from a URL slug if it exists
		local last_seen_no = tonumber(extra) or 0
		local logs = self.slash_service_request:read_logs(app_id, device_id, last_seen_no)
		
		-- nothing to read, so defer for long polling
		if logs and #logs == 0 and not context.deferred_once then
			context.deferred_once = true
			worker:defer(':' .. app_id .. ':' .. device_id, request, context, response, function ()
				-- timeout
				response:set_output({})
				return true
			end)		
			-- successfully deferred
			return
		end
		
		return logs
	end
		
	function slash_http_handler:api_push(app_id, device_id, extra, request, context, response)
		-- one log as a slug, or JSON log array
		local logs = request:json().logs
		if logs and #logs > 0 then
			for _, log in ipairs(logs) do
				self.slash_service_push:push_log(app_id, device_id, log)
			end
		end
		if extra then
			self.slash_service_push:push_log(app_id, device_id, extra)
		end
	end
		
	function slash_http_handler:handle_cached_static_content(path, request, context, response)
		-- set a default path for static content if not given
		if not path or path == '' then
			path = 'index.html'
		elseif path:sub(-1, -1) == '/' then
			path = path .. 'index.html'
		end
		-- rewrite the path to the currently processed path
		request:rewrite_url_path(path)
		-- set client side cache controls to match the server
		if self.cache_seconds == 0 then
			response:set_header('cache-control', 'no-store')
		else
			response:set_header('cache-control', 'max-age=' .. self.cache_seconds)
		end
		
		-- see if we have a valid cached result to reuse
		local time = utc_time()
		local cache_key = path
		local cache_entry = self.cache:get(cache_key)
		
		-- if the cache entry is expired then clear it
		if cache_entry and cache_entry.time + self.cache_seconds < time then
			self.cache:clear(cache_key)
			cache_entry = nil
		end
		
		-- if the cache entry is valid then return it as a result
		if cache_entry then
			if cache_entry.success then
				response:set_header('content-type', cache_entry.type)
				response:set_body(cache_entry.body)
				return true
			else
				return false
			end
		end
		
		-- attempt to retrieve the file from the static path
		local static = static_handler(self.static_path, nil, false)
		local result = static:handle(request, context, response)
		if result then
			-- cache this result
			if self.cache_seconds > 0 then
				self.cache:set(cache_key, {
					success = true,
					time = time,
					type = response:get_header('content-type'),
					body = response.body,
				})
			end
			return true
		end
		
		-- record our failure in the cache
		if self.cache_seconds > 0 then
			self.cache:set(cache_key, {
				success = false,
				time = time,
			})
		end
		return false
	end
	
end)