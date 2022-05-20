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
for i = 1, 5 do
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
		root.groups:push(group)
	end
	
	-- and a number of players, assign the players to a random group
	for p = 1, 1000 do
		local player = root:create({ id = 'player:' .. p })
		root.players[player.id] = player
		player.group = root.groups[math.random(1, root.groups:length())]
		player.group.players:push(player)
	end
	
	db:commit_transaction()
end

-- reopen the in memory worlds at a later time
for i = 1, #worlds do
	log('loading ' .. worlds[i])
	local root = silage(db, worlds[i])
	root:rewrite_log()
	for group_id, group in root.groups:ipairs() do
		log('group ' .. group_id .. ' players: ' .. group.players:length())
		
		-- update the data in some way
		group.players:remove(math.random(1, group.players:length()))
		group.players:find(function (p) return p.id:find('3') end)
		group.players:find_all(function (p) return p.id:find('3') end):with_each(function (p)
			p.flag = true
		end)
	end	
end

for i = 1, #worlds do
	log('loading ' .. worlds[i])
	local root = silage(db, worlds[i])
	log('flagged ' .. #root.players:find_all(function (p) return p.flag end))
end

log('done')