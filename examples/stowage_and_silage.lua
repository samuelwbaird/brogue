-- demonstrate the stowage, nosql DB, and the silage cache
-- copyright 2019 Samuel Baird MIT Licence

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
log('opening db/stowage.sqlite')
local db = stowage('db/stowage.sqlite')

log('remove previous data before testing')
db:remove_keys('room:')
db:remove_keys('cat:')
db:remove_keys('mouse:')

-- this house contains a number of rooms
log('create some rooms')
local rooms = array()
for i = 1, 20 do
	rooms:push(db:create_new('room:', { name = 'room' .. i }, { 'room' .. i }))
end

-- each room starts with a number of mice
log('put some mice in the rooms')
local mouse_count = 0
rooms:with_each(function (room)
	local number_of_mice = math.random(10, 20)
	for m = 1, number_of_mice do
		mouse_count = mouse_count + 1
		db:create_new('mouse:',
			-- the information for this mouse
			{ name = 'mouse' .. mouse_count, room = room },
			-- the reverse keys by which we may need to find this mouse
			{ 'room:mouse:' .. room })
	end
end)

-- this house contains a number of cats
log('create some cats')
for i = 1, #rooms / 2 do
	-- pick a random room for this cat
	local room = rooms[math.random(1, #rooms)]
	db:create_new('cat:',
		-- the information for this cat
		{ name = 'cat' .. i, room = room },
		-- the reverse keys by which we may need to find this cat
		{ 'room:cat:' .. room })
end

-- define a sort of pseudo game backend to exercise the DB
local model = {}
function model.get_cats_for_room(room)
	return db:reverse_query('room:cat:' .. room)
end

function model.get_mice_for_room(room)
	return db:reverse_query('room:mouse:' .. room)
end

function model.move_cat_to_room(cat, room)
	local data = db:get_value(cat)
	if data.room ~= room then
		data.room = room
		db:set_value(cat, data, { 'room:cat:' .. room })
	end
end

function model.move_mouse_to_room(mouse, room)
	local data = db:get_value(mouse)
	if data.room ~= room then
		data.room = room
		db:set_value(mouse, data, { 'room:mouse:' .. room })
	end
end

-- define a game update function that updates all entities in a room
function model.update(room)
	-- get all the entities in the room
	local cats = model.get_cats_for_room(room)
	local mice = model.get_mice_for_room(room)
	
	cats:with_each(function (cat)
		-- every turn a cat randomly pats some mice on the head
		for i = 1, 100 do
			local mouse = mice[math.random(1, #mice)]
			if mouse then
				db:log_append(mouse, {
					event = 'got_patted',
					cat = cat,
				})
			end
		end
		
		-- sometime the cat may choose to move room, but they are pretty lazy about it
		if math.random(1, 20) then
			local new_room = rooms[math.random(1, #rooms)]
			model.move_cat_to_room(cat, new_room)
		end
	end)
	
	mice:with_each(function (mouse)
		-- each mouse in the room checks it log of events
		local data = db:get_value(mouse)
		-- catch up the state of the mouse with the events that have occured
		local as_at_log_id = data.as_at_log_id or 0
		local pats = data.pats or 0
		db:log_read(mouse, as_at_log_id):with_each(function (log)
			if log.data.event == 'got_patted' then
				pats = pats + 1
			end
			last_log_event = log.id
		end)
		-- update these coalesced values and clear the log
		data.pats = pats
		data.as_at_log_id = as_at_log_id
		db:set_value(mouse, data)
		db:log_clear(mouse, last_log_event)
		
		-- if the mouse has been petted a certain number of times, it dies of embarrassment
		if pats > 30 then
			log(data.name .. ' has died of embarrassment')
			db:remove(mouse)
		end
	end)
end

-- run the game for a number of iterations to exercise the DB
log('running game iterations')
for iterations = 1, 1000 do
	if iterations % 100 == 0 then
		log(iterations)
	end
	rooms:with_each(function (room)
		-- update each room in its own DB transaction or its super slow
		db.db:transaction(function ()
			model.update(room)
		end)
	end)
end

-- now test out using a cache layer for derived values
local cache = silage(1024)

-- substitute in the key game methods to use the cache where possible
-- model.get_cats_for_room
-- model.get_mice_for_room
-- model.move_mice_to_room
-- model.move_cat_to_room

-- log('running game iterations - using silage cache')
-- for iterations = 1, 1000 do
-- 	if iterations % 100 == 0 then
-- 		log('  ' .. iterations)
-- 	end
-- 	rooms:with_each(function (room)
-- 		update(room)
-- 	end)
-- end

-- all done, sqlite command line can be used to view the data, eg. sqlite3 db/stowage.sqlite
db:close()
log('done')