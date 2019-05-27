-- demonstrate the stowage, nosql DB, as a sort of game backend
-- copyright 2019 Samuel Baird MIT Licence

-- reference the brogue libraries
package.path = '../source/?.lua;' .. package.path

-- load the modules we need
local array = require('core.array')
local stowage = require('dweeb.stowage')

log = function (text)
	print(os.date('!%F %T UTC ')  .. tostring(text or ''))
end

-- open up a database for some testing
log('opening db/stowage.sqlite')

-- on disk store
local db = stowage('db/stowage.sqlite', true)

-- in memory story
-- local db = stowage(nil)

-- define a sort of pseudo game backend to exercise the DB
local model = {}

function model.reset()
	log('remove previous data before testing')
	db:remove_keys('room:')
	db:remove_keys('cat:')
	db:remove_keys('mouse:')

	-- this house contains a number of rooms
	log('create some rooms')
	model.rooms = array()
	for i = 1, 20 do
		model.rooms:push(db:create_new('room:', { name = 'room' .. i }, { 'room' .. i }))
	end

	-- each room starts with a number of mice
	log('put some mice in the rooms')
	local mouse_count = 0
	model.rooms:with_each(function (room)
		local number_of_mice = math.random(1, 20)
		for m = 1, number_of_mice do
			mouse_count = mouse_count + 1
			db:create_new('mouse:',
				-- the information for this mouse
				{
					name = 'mouse' .. mouse_count,
					room = room,
					pats = 0,
					as_at_log_id = 0,
					unique_cats = {},
					cat_count = 0,
				},
				-- the reverse keys by which we may need to find this mouse
				{ 'room:mouse:' .. room })
		end
	end)

	-- this house contains a number of cats
	log('create some cats')
	for i = 1, 10 do
		-- pick a random room for this cat
		local room = model.rooms[math.random(1, #model.rooms)]
		db:create_new('cat:',
			-- the information for this cat
			{ name = 'cat' .. i, room = room },
			-- the reverse keys by which we may need to find this cat
			{ 'room:cat:' .. room })
	end
end

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
		for i = 1, 4 do
			if #mice > 0 then
				local mouse = mice[math.random(1, #mice)]
				db:log_append(mouse, {
					event = 'got_patted',
					cat = cat,
				})
			end
		end
		
		-- sometime the cat may choose to move room, but they are pretty lazy about it
		if math.random(1, 20) == 1 then
			local new_room = model.rooms[math.random(1, #model.rooms)]
			model.move_cat_to_room(cat, new_room)
		end
	end)
	
	mice:with_each(function (mouse)
		-- each mouse in the room checks it log of events
		local data = db:get_value(mouse)
		-- catch up the state of the mouse with the events that have occured
		db:log_read(mouse, data.as_at_log_id):with_each(function (log)
			if log.data.event == 'got_patted' then
				data.pats = data.pats + 1
				-- track how many unique cats have patted this mouse
				if not data.unique_cats[log.data.cat] then
					data.unique_cats[log.data.cat] = true
					data.cat_count = data.cat_count + 1
				end
			end
			data.as_at_log_id = log.id
		end)
		-- update these coalesced values and clear the log
		db:set_value(mouse, data)
		db:log_clear(mouse, data.as_at_log_id)
		
		if data.cat_count == 10 then
			-- if the mouse has been petted by all the cats
			log(data.name .. ' has died of embarrassment')
			db:remove(mouse)
			
		elseif data.pats >= 5 then
			-- if the mouse has been petted a bit it wants to scurry away
			local new_room = model.rooms[math.random(1, #model.rooms)]
			model.move_mouse_to_room(mouse, new_room)
			
			-- reset the pat count before the next move
			data.pats = 0
			db:set_value(mouse, data)
		end
	end)
end

-- run the game for a number of iterations to exercise the DB
log('running game iterations')
model.reset()
for iterations = 1, 1000 do
	if iterations % 100 == 0 then
		log(iterations)
	end
	-- biggest difference to speed is combining updates in a transaction
	db:transaction(function ()
		model.rooms:with_each(function (room)
			model.update(room)
		end)
	end)
end

-- all done, sqlite command line can be used to view the data, eg. sqlite3 db/stowage.sqlite
db:close()
log('done')