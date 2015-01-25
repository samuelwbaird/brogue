-- a package to handle various types of dispatch
-- frame based delays
-- co-routines with their own environment and some conveniences
-- a weave of many co-routines
-- copyright 2014 Samuel Baird MIT Licence

local coroutine = require('coroutine')

local class = require('core.class')
local array = require('core.array')

-- update set, call update on each object, returning true
-- means this object is finished and should be removed from the update set
-- all update objects can also be tagged, and removed by tag
-- needs to handle update during iteration
-- efficient reverse indexing might be good too

local update_set = class(function (update_set)
	local super = update_set.new

	function update_set.new(update_function)
		local self = super()
		self.update_function = update_function
		
		self.is_updating = false
		self.has_removals = false
		self.set = {}
		self.remove_set = {}
		
		return self
	end
	
	function update_set:add(obj, tag)
		self.set[#self.set + 1] = { obj, tag }
	end
	
	function update_set:update(update_function)
		assert(not self.is_updating, 'update during update')

		-- update during iteration
		-- allow but ignore additions during iteration
		-- respect removals during iterations, but collect and mutate only after the update
		self.is_updating = true
		
		local fn = update_function or self.update_function
		local index = 0
		local set = self.set
		local remove_set = self.remove_set
		local count = #set
		
		while index < count do
			index = index + 1
			local entry = set[index]
			
			-- skip 'removed' entries
			if (not remove_set) or remove_set[entry] == nil then
				-- use a provided function or assume the obj itself is a function
				local result = fn and fn(entry[1]) or entry[1]()
			
				-- if true then this object is no longer required
				if result then
					self.has_removals = true
					remove_set[entry] = true
				end
			end
		end
		
		if self.has_removals then
			self:do_removals()
		end
		
		self.is_updating = false
	end
	
	function update_set:clear()
		if self.is_updating then
			self.has_removals = true
			for _, entry in ipairs(self.set) do
				self.remove_set[entry] = true
			end
		else
			self.set = {}
		end
	end
	
	function update_set:remove(tag_or_obj)
		for _, entry in ipairs(self.set) do
			if entry[1] == tag_or_obj or entry[2] == tag_or_obj then
				self.has_removals = true
				self.remove_set[entry] = true
			end
		end
		
		if not self.is_updating then
			self:do_removals()
		end
	end
	
	function update_set:is_empty()
		return #set > 0
	end
	
	function update_set:do_removals()
		local new_set = {}
		for _, entry in ipairs(set) do
			if not remove_set[entry] then
				new_set[#new_set + 1] = entry
			end
		end

		self.set = new_set
		self.remove_set = {}
		self.has_removals = false
	end
	
end)

-- dispatch
local dispatch = class(function (dispatch)
	local super = dispatch.new
	
	function dispatch.new()
		local self = super()
		self.update_set = update_set()
		return self
	end
	
	-- call in this many steps/ticks/frames
	function dispatch:delay(count, fn, tag)
		assert(count > 0, 'delay count must be greater than 0')
		self.update_set:add({
			type = 'delay',
			count = count,
			delay_fn = fn,
		}, tag)
	end
	
	-- call for this number of steps/ticks/frames
	function dispatch:recur(count, fn, tag)
		self.update_set:add({
			type = 'delay',
			count = count,
			repeat_fn = fn,
		}, tag)
	end
	
	-- call this every time
	function dispatch:hook(fn, tag)
		self:recur(-1, fn, tag)
	end
	
	-- call this once only
	function dispatch:once(fn, tag)
		self:recur(1, fn, tag)
	end
	
	-- schedule a co-routine to be resumed each update until complete
	function dispatch:schedule(co, tag)
		self.update_set:add({
			type = 'schedule',
			co = co,
		}, tag)
	end
	
	-- wrap a function as a co-routine
	function dispatch:wrap(fn, tag)
		self:schedule(coroutine.create(fn), tag)
	end
	
	-- update, next round of dispatch/tick/frame
	local function update_function(entry)
		if entry.co then
			-- resume the co-routine until it's dead
			coroutine.resume(entry.co)
			if coroutine.status(entry.co) == 'dead' then
				return true
			end
		else
			if entry.repeat_fn then
				entry.repeat_fn()
			end
			if entry.count and entry.count > 0 then
				entry.count = entry.count - 1
				if entry.count == 0 then
					if entry.delay_fn then
						entry.delay_fn()
					end
					-- finished now
					return true
				end
			end
		end
	end
	
	function dispatch:update()
		self.update_set:update(update_function)
	end
	
	-- proxy through some methods from the update_set
	
	function dispatch:clear()
		self.update_set:clear()
	end
	
	function dispatch:remove(tag_or_fn)
		self.update_set:remove(tag_or_fn)
	end
	
	function dispatch:is_empty()
		return self.update_set:is_empty()
	end
	
end)

-- threads added to the weave are wrapped in this class
local thread = class(function (thread)
	local super = thread.new
	
	function thread.new(weave, thread_function)
		local self = super()
		self.weave = weave
		self.globals = {}
		
		-- lazily created dispatch objects
		self.on_update = nil
		self.on_resume = nil
		self.on_suspend = nil
		
		-- set up the local convenience stuff for this thread
		
		
		-- create the co-routine
		if thread_function then
			self:run(thread_function)
		end
		
		return self
	end
	
	function thread:update()
		-- if we have an on_update then dispatch it
			
			
		-- if this thread is waiting on something (eg. a yield number of frames)
		-- then check the wait condition
			
		-- if we have a co-routine then resume it



	end
	
	function thread:run(thread_function)
		setfenv(thread_function, self.globals)
		self.coroutine = coroutine.create(thread_function)
	end

end)

-- the weave class manages a bunch of threads
local weave = class(function (weave)
	local super = weave.new
	
	function weave.new()
		local self = super()
		self.shared_globals = {}
		return self
	end
	
	function weave:update()
		-- update all threads
	end
	
	-- shared globals
	
	-- new thread (function, globals)
	-- add thread
	-- remove thread
	-- clear or remove by tag

	-- from inside a thread
	-- delay (condition)
	-- suspend/remove (remove references)
	-- resume ()
	-- update
	-- exit
	-- -> run this thread and wait for it to complete
	-- -> detach this thread separately
	-- -> how about detaching a micro-delay? in five ticks of this thread reset this flag and run this function
	
	-- simplest model is all threads retained and 'updated' with each tick
	-- each condition is just checked every frame for every thread
	-- this might have too much overhead, trigger conditions could just suspend, resume? perhaps allow GC of waiting threads
	-- simplest might be the best initial approach
	
	-- each thread have its own globals (as well as shared)
	-- each thread have a on_update, on_suspend, on_resume, on_begin hook

end)

-- publish the package of classes, default to constructing a dispatch object
return class.package({ update_set, dispatch, thread, weave }, dispatch.new)