-- compare searching data using sqlite, brute force search and indexed lua tables
-- copyright 2014 Samuel Baird MIT Licence

-- reference the brogue libraries
package.path = '../source/?.lua;' .. package.path

-- load the modules we need
local array = require('core.array')
local sqlite = require('dweeb.sqlite')
local random_key = require('rascal.util.random_key')

local number_of_items = 1000
local number_of_searches = 10000
local repeat_count = 50
local method = 2

-- first get a sample set of X number of objects
local items = array()
for i = 1, number_of_items do
	items:push(random_key.printable(6))
end

-- store
local db = nil
local all = array()

if method == 1 then
	db = sqlite() --'db/test.sqlite', true)
	db:prepare_table('test', {
		columns = {
			{ name = 'code', type = 'TEXT' },
		},
		indexes = {
			{ columns = { 'code' }, type = 'INDEX' }
		},
	})
	db:transaction(function ()
		for _, code in ipairs(items) do
			db:insert('test', { code = code })
		end
	end)
elseif method == 2 or method == 3 then
	for _, code in ipairs(items) do
		all:push(code)
	end
end

local searches = array()
while #searches < number_of_searches and #items > 0 do
	local index = math.random(1, #items)
	searches:push(items[index])
	table.remove(items, index)
end

-- repeat a search for specific items X number of times
for r = 1, repeat_count do
	local dict = nil
	if method == 3 then
		-- prepare a dictionary each time
		dict = {}
		for _, code in ipairs(all) do
			local entry = dict[code]
			if not entry then
				entry = array()
				dict[code] = entry
			end
			entry:push(_)
		end
	end
	
	for _, search in ipairs(searches) do
		-- find by sqlite
		if method == 1 then
			local row = db:select('test', '*', {code = search })
			assert(row.code ~= search)
		elseif method == 2 then
			for _, code in ipairs(all) do
				if code == search then
					break
				end
			end
		end
			
	end
end