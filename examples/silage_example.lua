-- demonstrate using db back in memory objects with silage
-- copyright 2020 Samuel Baird MIT Licence

-- reference the brogue libraries
package.path = '../source/?.lua;' .. package.path

-- load the modules we need
local array = require('core.array')
local stowage = require('dweeb.stowage')
local silage = require('dweeb.silage')

log = function (text)
	print(os.date('!%F %T UTC ')  .. tostring(text or ''))
end

-- open up a database for some testing
log('opening db/silage.sqlite')
local db = stowage('db/silage.sqlite', true)
-- create a number of silage worlds
local worlds = array()
for i = 1, 1 do
	db:begin_transaction()
	-- create a new key in the DB for this silage object
	local world = db:create_new('world:')
	worlds:push(world)
	
	-- create an in memory set of objects to work with
	log('creating ' .. world)
	local root = silage(db, world)
	root.groups = root:create()
	root.players = root:create()
	
	-- create a number of groups
	for g = 1, 10 do
		local group = root:create({ id = 'group:' .. g })
		group.players = root:create()
		root.groups[g] = group
	end
	
	-- and a number of players, assign the players to a random group
	for p = 1, 100 do
		local player = root:create({ id = 'player:' .. p })
		root.players[player.id] = player
		player.group = root.groups[math.random(1, root.groups:length())]
		player.group.players[player.id] = player
	end
	
	db:commit_transaction()
end

-- reopen the in memory worlds at a later time
for i = 1, #worlds do
	log('loading ' .. worlds[i])
	local root = silage(db, worlds[i])
end


log('done')