-- example of queue tasks to a task server pool
-- including multiple yields from a task generating further tasks
--
-- copyright 2016 Samuel Baird MIT Licence

-- reference the brogue libraries
package.path = '../source/?.lua;' .. package.path

-- use rascal
local rascal = require('rascal.core')
local task_server = require('rascal.util.task_server')

-- configure logging
rascal.log_service:log_to_console(true)

-- create a task server with a pool of worker threads
local tasks = task_server(8)

local generate_tasks = [==[
log('begin generator task')
for i = 1, count do
	-- perform pretend work
	for i = 1, 100000000 do
		local waste = { i }
	end
	-- return multiple results
	yield(i)
end
log('all tasks queued')
]==]

local second_stage_task = [==[
log('begin second stage task ' .. index_no)
-- perform pretend work
for i = 1, 100000000 * index_no do
	local waste = { i }
	if i == 1000000 + index_no then
		queue_lua([===[
		log('shard task from worker ' .. i)
		]===], { i = i })
	end
end
]==]

-- queue up a bunch of stage 1 tasks
tasks:queue_lua(generate_tasks, { count = 20 }, function (task_no)
	log('generator task yielded ' .. task_no)
	tasks:queue_lua(second_stage_task, { index_no = task_no })
end)

-- run the main loop until all tasks are complete and close on complete
tasks:complete(true)
