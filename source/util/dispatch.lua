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
	
	function update_set:init(update_function)
		self.update_function = update_function
		
		self.is_updating = false
		self.has_removals = false
		self.set = {}
		self.remove_set = {}
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
			if (not remove_set) or (remove_set[entry] == nil) then
				-- use a provided function or assume the obj itself is a function
				local result = nil
				if fn then
					result = fn(entry[1])
				else
					result = entry[1]()
				end
			
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
	
	function update_set:get(tag_or_obj)
		local out = {}
		for _, entry in ipairs(self.set) do
			if entry[1] == tag_or_obj or entry[2] == tag_or_obj then
				out[#out + 1] = entry[1]
			end
		end
		return out
	end
	
	function update_set:remove(tag_or_obj)
		for _, entry in ipairs(self.set) do
			if entry[1] == tag_or_obj or entry[2] == tag_or_obj then
				self.has_removals = true
				self.remove_set[entry] = true
			end
		end
		
		if not self.is_updating and self.has_removals then
			self:do_removals()
		end
	end
	
	function update_set:is_empty()
		return #self.set > 0
	end
	
	function update_set:do_removals()
		local new_set = {}
		for _, entry in ipairs(self.set) do
			if not self.remove_set[entry] then
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
	
	function dispatch:init()
		self.update_set = update_set()
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
			type = 'recur',
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
	
	dispatch.dispatch = dispatch.update
	
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
	-- lazily created dispatch objects
	thread:lazy({
		on_update = function () return dispatch() end,
		on_suspend = function () return dispatch() end,
		on_resume = function () return dispatch() end,
		on_exit = function () return dispatch() end,
	})
	
	function thread:init(weave, tag, thread_function, ...)
		self.weave = weave
		self.tag = tag
		
		-- customise the environment for the thread
		self.globals = {
			thread = self,
			weave = weave,
			tag = tag,			
		}
		setmetatable(self.globals, {
			__index = weave.shared_globals
		})
		
		-- lazy access to on_update dispatch functions
		self.globals.delay = function (...) self.on_update:delay(...) end
		self.globals.recur = function (...) self.on_update:recur(...) end
		self.globals.hook = function (...) self.on_update:hook(...) end
		self.globals.schedule = function (...) self.on_update:schedule(...) end
		self.globals.wrap = function (...) self.on_update:wrap(...) end
		
		-- set up the local convenience stuff for this thread
		local proxies = { 'suspend', 'resume', 'execute', 'tagged_run', 'run', 'yield', 'exit', 'call', 'wait' }
		for _, proxy in ipairs(proxies) do
			self.globals[proxy] = function (...)
				self[proxy](self, ...)
			end
		end
		
		-- create the co-routine
		self:execute(thread_function, ...)
	end
	
	function thread:suspend()
		self.weave:suspend(self)
	end
	
	function thread:resume()
		self.weave:resume(self)
	end
	
	function thread:safe_update(on_error)
		local success, result = pcall(thread.update, self)
		if not success then
			self.error = result
			if on_error then
				on_error(result)
			end
			return true
		else
			return result
		end
	end
	
	function thread:update()
		-- if we have an on_update then dispatch it
		if rawget(self, 'on_update') then
			self.on_update:update()
		end
			
		-- if this thread is waiting on something (eg. a yield number of frames)
		-- then check the wait condition
		if self.wait_condition then
			if type(self.wait_condition) == 'number' then
				self.wait_condition = self.wait_condition - 1
				if self.wait_condition > 0 then
					return false
				end
			elseif type(self.wait_condition) == 'function' then
				local check = self.wait_condition()
				if not check then
					return false
				end
			end
		end
		
		-- if we have continued then the wait condition must have cleared
		self.wait_condition = nil
		
		-- continue execution
		if self.coroutine and coroutine.status(self.coroutine) ~= 'dead'then
			local success, e = coroutine.resume(self.coroutine)
			if not success then
				error(e)
			end
		end
	
		-- if we're complete then exit
		if not self.coroutine or coroutine.status(self.coroutine) == 'dead' then
			if rawget(self, 'on_exit') then
				self.on_exit:update()
			end
			return true
		end
	end
	
	-- thread functions, proxied into functions in the thread environment
	
	-- transfer the main thread into this function with no return
	function thread:execute(thread_function, ...)
		local yield_after = self.coroutine ~= nil and self.coroutine == coroutine.running()
		
		setfenv(thread_function, self.globals)
		self.coroutine = coroutine.create(thread_function)
		
		-- run this coroutine until yield
		local success, e = coroutine.resume(self.coroutine, ...)
		if not success then
			error(e)
		end
		
		if yield_after then
			-- yield out of the original
			coroutine.yield()
		end
	end
	
	-- call into another co-routine until it completes then resume the current one
	function thread:call(sub_thread_function, ...)
		setfenv(sub_thread_function, self.globals)
		sub_thread_function(...)
	end
	
	-- set up another thread in parallal
	function thread:run(thread_function, ...)
		return self.weave:thread(thread_function, ...)
	end
	
	function thread:tagged_run(tag, thread_function, ...)
		return self.weave:tagged_thread(tag, thread_function, ...)
	end
	
	function thread:yield(wait_condition)
		self.wait_condition = wait_condition
		coroutine.yield()
	end
	
	thread.wait = thread.yield
	
	function thread:exit()
		self.wait_condition = nil
		self.coroutine = nil
		coroutine.yield()
	end

end)

-- the weave class manages a bunch of threads
local weave = class(function (weave)
	
	function weave:init(environment)
		self.shared_globals = {}
		setmetatable(self.shared_globals, { __index = environment or _G })
		
		self.update_set = update_set()
		self.suspend_set = update_set()
	end
	
	-- new, suspend, resume
	
	function weave:thread(thread_function, ...)
		return self:tagged_thread(nil, thread_function, ...)
	end
	
	function weave:tagged_thread(tag, thread_function, ...)
		local t = thread(self, tag, thread_function, ...)
		self.update_set:add(t, tag)
		return t
	end
	
	-- load thread code from file
	function weave:loadfile(filename, ...)
		local agent = assert(loadfile(filename))
		self:tagged_thread(filename, agent, ...)
	end
	
	function weave:suspend(thread_or_tag)
		local set = self.update_set:get(thread_or_tag)
		if #set > 0 then
			self.update_set:remove(thread_or_tag)
			for _, thread in ipairs(set) do
				self.suspend_set:add(thread, thread.tag)
				if rawget(thread, 'on_suspend') then
					thread.on_suspend:update()
				end
			end
		end
	end
	
	function weave:resume(thread_or_tag)
		local set = self.suspend_set:get(thread_or_tag)
		if #set > 0 then
			self.suspend_set:remove(thread_or_tag)
			for _, thread in ipairs(set) do
				self.update_set:add(thread, thread.tag)
				if rawget(thread, 'on_resume') then
					thread.on_resume:update()
				end
			end
		end
	end
	
	-- clear and remove
	
	function weave:clear()
		self.update_set:clear()
		self.suspend_set:clear()
	end
	
	function weave:remove(thread_or_tag)
		self.update_set:remove(thread_or_tag)
		self.suspend_set:remove(thread_or_tag)
	end
	 
	-- update
	
	function weave:safe_update(on_error)
		self.update_set:update(function (thread)
			return thread:safe_update(on_error)
		end)
	end	
	
	function weave:update()
		self.update_set:update(function (thread)
			thread:update()
		end)
	end

end)

-- publish the package of classes, default to constructing a dispatch object
return class.package({ update_set = update_set, dispatch = dispatch, thread = thread, weave = weave }, dispatch.new)