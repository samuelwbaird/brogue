-- demonstrate basic DB access with dweeb
-- copyright 2014 Samuel Baird MIT Licence

-- reference the brogue libraries
package.path = '../source/?.lua;' .. package.path

-- load the modules we need
local sqlite = require('dweeb.sqlite')
local random_key = require('rascal.util.random_key')

-- open up a database for some testing
print('opening db/basic_db.sqlite')
local db = sqlite('db/basic_db.sqlite')		-- nil name = in memory db

-- execute raw sql
db:exec('DROP TABLE IF EXISTS `codes`')

-- use a convenience command to prepare table
db:prepare_table('codes', {
	columns = {
		{ name = 'id', type = 'INTEGER PRIMARY KEY AUTOINCREMENT' },
		{ name = 'code', type = 'TEXT' },
	},
	indexes = {
		-- no other indexes needed
	},
})

-- insert a bunch of short random codes into the table for our tests
-- do this work within a single transaction to improve throughput
	
print('insert a large volume short codes into out table')
db:transaction(function ()
	for i = 1, 200000 do
		db:insert('codes', {
			code = random_key.printable(3)	-- use short printable codes
		}):execute()
	end
end)

-- find out how many unique codes were generated
print('total code in the table ' .. db:query('SELECT COUNT(*) FROM codes'):value())
print('unique codes in the table ' .. db:query('SELECT COUNT(DISTINCT(code)) FROM codes'):value())

-- prepare an SQL statement, then re-use it
-- prepare a select on table test, selecting id and code, using code as the criteria
local select_statement = db:select('codes', 'id, code' , { 'code' }):prepare()

-- lets find the id of a bunch of codes if they are present
for i = 1, 10 do
	local code = random_key.printable(3)
	print('selecting code ' .. code)
	select_statement:query({ code }):with_each(function (row)
		print('found this code in row id ' .. row.id)
	end)
end

-- sql can be executed directly, built, then queried, or prepared for multiple queries
-- the following approaches could all be used to delete rows

print('deleting some rows')

-- sql string + bindings
db:execute('DELETE FROM codes WHERE id = ?', { 10 })

-- sql builder function + bindings + execute
db:delete('codes', { id = 11 }):execute()

-- sql builder function + empty bindings + prepare, then reused
local delete_statement = db:delete('codes', { 'id' }):prepare()
delete_statement:execute({ 12 })
delete_statement:execute({ 13 })
delete_statement:execute({ 14 })

-- now an sql update using our builder
-- showing bindings with values supplied directly, and bindings with operators specified

print('updating some rows')
db:update('codes', { code = 'blank' }):where({ ['id <='] = 10 }):execute()

-- now let's check if our delete and updates worked, using bindings with
-- operators appended, and an id range from 8 to 16

print('searching rows between 8 and 16')
db:select('codes', 'id, code', { 'id >=', 'id <=' }):query({ 8, 16 }):with_each(function (row)
	print('found ' .. row.id .. ' ' .. row.code)
end)

-- close db
db:close()
-- all done, sqlite command line can be used to view the data, eg. sqlite3 db/basic_db.sqlite
print('done')