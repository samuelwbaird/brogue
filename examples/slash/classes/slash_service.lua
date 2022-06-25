local class = require('core.class')
local array = require('core.array')

local sqlite = require('dweeb.sqlite')
local stowage = require('dweeb.stowage')
local rascal = require('rascal.core')

return class(function (slash_service)
	
	-- api definitions ----------------------------------------------------
	local request_api = {
		read_apps = '-> app_ids:[]',
		read_devices = 'app_id:string -> device_ids:[]',
		read_logs = 'app_id:string, device_id:string, last_seen:int -> logs:[]',
	}
	
	local push_api = {
		push_log = 'app_id:string, device_id:string, log:string',
	}
	
	local publish_api = {
		signal = 'key:string',	-- :, :app_id, :app_id:device_id
	}
	
	-- service init ------------------------------------------------------
	function slash_service:init(log_retain_seconds, endpoint_prefix)
		self.log_retain_seconds = log_retain_seconds
		
		-- we're going to work with an in memory data store only
		self.logs_by_app = {}	-- app_id -> device_id -> logs[]
		self.log_no = 0
		
		-- publish all APIs
		proxy_server(self, request_api, endpoint_prefix .. 'slash_service.request', zmq.REP, 'slash_service.request')
		proxy_server(self, push_api, endpoint_prefix .. 'slash_service.push', zmq.PULL, 'slash_service.push')
		self.publish = proxy_server(self, publish_api, endpoint_prefix .. 'slash_service.publish', zmq.PUB, 'slash_service.publish')
		
		-- soak up updates to signal
		self.soak = {}
		loop:add_interval(250, self:delegate(self.unsoak))
		
		-- update the app and device list periodically
		self.app_and_device_list = {}
		loop:add_interval(3000, self:delegate(self.update_app_and_device_list))
		
		-- expire logs periodically
		loop:add_interval(10000, self:delegate(self.expire_logs))
	end
	
	function slash_service:signal_logs(app_id, device_id)
		self.soak[':' .. app_id .. ':' .. device_id] = true
	end
	
	function slash_service:unsoak()
		-- signal when long poll log watchers have an update
		for key in pairs(self.soak) do
			self.publish:signal(key)
		end
		self.soak = {}
	end
	
	function slash_service:update_app_and_device_list()
		-- create a freshly ordered list
		self.app_and_device_list = {}
		local app_list = array()
		for app_id, devices in pairs(self.logs_by_app) do
			local devices_by_time = array()
			for device_id, logs in pairs(devices) do
				devices_by_time:push({
					device_id = device_id,
					time = logs[#logs].time,
				})
			end
			devices_by_time:sort(function (d1, d2)
				return d1.time > d2.time
			end)
			self.app_and_device_list[app_id] = devices_by_time
			app_list:push({
				app_id = app_id,
				time = devices_by_time[1].time,
			})
		end
		app_list:sort(function (d1, d2)
			return d1.time > d2.time
		end)
		self.app_and_device_list[''] = app_list
	end
	
	function slash_service:expire_logs()
		local cutoff = utc_time() - self.log_retain_seconds
		for app_id, devices in pairs(self.logs_by_app) do
			local empty = true
			for device_id, logs in pairs(devices) do
				while logs[1].time < cutoff do
					logs:remove(1)
				end				
				if #logs > 0 then
					empty = false
				else
					devices[device_id] = nil
				end
			end
			if empty then
				self.logs_by_app[app_id] = nil
				self.last_devices_update[app_id] = nil
			end
		end
	end
	
	function slash_service:read_apps()
		return self.app_and_device_list[''] or {}
	end
	
	function slash_service:read_devices(app_id)
		return self.app_and_device_list[app_id] or {}
	end
	
	function slash_service:read_logs(app_id, device_id, last_seen_no)
		local output = {}
		local devices = self.logs_by_app[app_id]
		local device_log = devices and devices[device_id]
		if device_log then
			local out_index = 0
			for i, log in ipairs(device_log) do
				if log.no > last_seen_no then
					out_index = out_index + 1
					output[out_index] = log
					if out_index >= 512 then
						return output
					end
				end
			end
		end		
		return output
	end
	
	function slash_service:push_log(app_id, device_id, log_value)
		if #app_id < 4 or #app_id > 40 or #device_id < 8 or #device_id > 40 or (not log_value) then
			return
		end
		
		self.log_no = self.log_no + 1
		
		local devices = self.logs_by_app[app_id]
		if not devices then
			devices = {}
			self.logs_by_app[app_id] = devices
		end
		local device = devices[device_id]
		if not device then
			device = array()
			devices[device_id] = device
		end
		device:push({
			time = utc_time(),
			no = self.log_no,
			log_value = log_value,
		})
		self:signal_logs(app_id, device_id)
	end	
end)