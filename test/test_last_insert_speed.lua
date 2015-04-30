-- compare searching data using sqlite, brute force search and indexed lua tables
-- copyright 2014 Samuel Baird MIT Licence

-- reference the brogue libraries
package.path = '../source/?.lua;' .. package.path

-- load the modules we need
local sqlite = require('dweeb.sqlite')

local db = sqlite()
db:prepare_table('test', { 
	columns = {
		{ name = 'id', type = 'INTEGER PRIMARY KEY AUTOINCREMENT' },
		{ name = 'channel', type = 'TEXT' },
		{ name = 'expiry', type = 'INTEGER' },
		{ name = 'filter', type = 'TEXT' },
		{ name = 'type', type = 'TEXT' },
		{ name = 'data', type = 'TEXT' },
	},
})

db:insert('test', { channel = 'test' })
local cache = db:insert_id()

for i = 1, 1000000 do
	db:insert('test', { channel = 'test' })
	-- cache = cache + 1
	-- local i = cache
	local i = db:insert_id()
end