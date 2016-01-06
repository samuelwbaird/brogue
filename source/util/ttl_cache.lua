-- a time to live cache	
-- ttl measured in discrete ticks rather than quantities of time
-- tick the cache at whatever interval is required
-- access is bucketed for each tick (coarse grained)
-- copyright 2016 Samuel Baird MIT Licence

local math = require('math')

local class = require('core.class')
local array = require('core.array')

return class(function (ttl_cache)
	
	function ttl_cache:init(default_ttl)
		self.default_ttl = default_ttl or 0
		
		-- ttl buckets by tick
		self.bucket_offset = 0
		self.buckets = {}
		
		-- reference a value back to its bucket
		self.reverse = {}
	end
	
	function ttl_cache:get_bucket(ttl)
		if ttl < 0 then
			ttl = 0
		end
		local bucket_no = self.bucket_offset + math.ceil(ttl)
		local bucket = self.buckets[bucket_no]
		if not bucket then
			bucket = {}
			self.buckets[bucket_no] = bucket
		end
		return bucket
	end
	
	function ttl_cache:tick()
		local offset = self.bucket_offset
		-- remove all items from the reverse cache
		local bucket = self.buckets[offset]
		if bucket then
			for key, _ in pairs(bucket) do
				self.reverse[key] = nil
			end
		end
		-- remove the bucket
		self.buckets[offset] = nil		
		-- keep ticking forward
		self.bucket_offset = offset + 1
		-- return the bucket incase thats useful for cleanup
		return bucket
	end
	
	function ttl_cache:push(key, value, ttl)
		ttl = ttl or default_ttl
		-- remove old values/k 
		self:clear(key)
		-- set the value in the new bucket as required
		local bucket = self:get_bucket(ttl)
		bucket[key] = value
		self.reverse[key] = bucket
		-- return the value
		return value
	end
	
	function ttl_cache:clear(key)
		local bucket = self.reverse[key]
		if bucket then
			self.reverse[key] = nil
			bucket[key] = nil
		end		
	end
	
	ttl_cache.set = ttl_cache.push
	
	-- get the value and update its ttl
	function ttl_cache:get(key, keepalive_ttl)
		local bucket = self.reverse[key]
		if bucket then
			local value = bucket[key]
			if keepalive_ttl then
				local new_bucket = self:get_bucket(keepalive_ttl)
				if new_bucket ~= bucket then
					new_bucket[key] = value
					bucket[key] = nil
					self.reverse[key] = new_bucket
				end
			end
			return value
		end
		return nil
	end
	
	-- get the value without updating its ttl
	function ttl_cache:peek(key)
		local bucket = self.reverse[key]
		if bucket then
			return bucket[key]
		end
		return nil
	end
	
	ttl_cache.pull = ttl_cache.get

end)