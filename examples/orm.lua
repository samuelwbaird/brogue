-- reference the brogue libraries
package.path = '../source/?.lua;' .. package.path

-- demonstrate the light and loose ORM model
--
-- this demonstration introduces the grid and turn based game of runners and blockers
-- the runners must reach the other end of the field, the blockers must prevent them
-- the game is modelled using the dweeb ORM and changes are persisted
-- each time this script is run the game continues for a few more steps
-- demonstrating the persistence of data to the db
--
-- the rules
-- the game runs on a 7x7 grid, runners start at one end, blockers in the other half
-- there are 4 runners and two blockers
-- the runners move first, one at a time, then the blockers
-- runners must move to an unoccupied adjacent square
-- blockers may stay still or move to an unoccupied adjacent square
-- if at the end of any move a runner has reached the other end of the board runners win
-- if at the end of any move a runner is adjacent to a blocker then blockers wins


-- load the modules we need
local array = require('core.array')
local model = require('dweeb.model')

-- load a model with the assigned db file
print('open the model at db/game.sqlite')
local game_model = model('db/game.sqlite')

-- first thing, define all the classes in the model, and all their relationships
-- the model will ensure the appropriate tables in the database are created if they do no already exit
	
-- we will define our model with three classes, each in its own lua module
local model_classes = { 'field', 'position', 'blocker', 'runner' }
-- first stage, define all the classes
for _, class in ipairs(model_classes) do
	print('define ' .. class)
	require('model.' .. class):define_class(game_model)
end
print('add relationships')
-- second stage, define relationships between classes
for _, class in ipairs(model_classes) do
	require('model.' .. class):define_relationships(game_model)
end

-- the model is ready, now make sure the data is ready

print('')
local field = game_model.field(1)
if field then
	-- the field already exists in the db
	print('found existing field ' .. field.id)

else
	-- create a field and populate positions
	-- data updates must occur in a transaction
	game_model:transaction(function ()
		field = game_model.field:create({
			state = 'finished',
		})
		print('created field ' .. field.id)
	
		-- now create a grid of positions and populate the adjacent position and field
		local rows = array()
		for r = 1, 8 do
			rows[r] = array()
			for c = 1, 8 do
				rows[r][c] = game_model.position:create({
					-- set the reference back to the field (using the defined relationship)
					field = field,
					row = r,
					column = c,
					name = '[' .. c .. ':' .. r .. ']'
				})
			end
		end
	
		-- we can access the collection, with parameter of true to fetch the entire collection into an array
		print('field has ' .. #field:positions(true) .. ' positions')
		print('assign adjacent positions')
	
		-- we can set some arbitrary value on the objects, even complex things
		-- like arrays of references to other objects, without defining them first
		for r = 1, 7 do
			for c = 1, 7 do
				-- get the list of valid adjacent positions
				local adjacent = array()
				for r_offset = -1, 1 do
					if r + r_offset >= 1 and r + r_offset <= #rows then
						for c_offset = -1, 1 do
							if c + c_offset >= 1 and c + c_offset <= #rows[r] then
								if rows[r + r_offset][c + c_offset] ~= rows[r][c] then
									adjacent:push(rows[r + r_offset][c + c_offset])
								end
							end
						end
					end
				end
				-- set an array of adjacent positions on this position
				rows[r][c].adjacent = adjacent
			end
		end
		
		-- now we create the blockers and runners for the game
		-- we set their reference to the field, so they will be in the field list of all runners and blockers
		-- but not associated with specified
		print('create blockers and runners')
		for i = 1, 4 do
			game_model.runner:create({
				name = 'r' .. i,
				field = field,
			})
		end
		for i = 1, 2 do
			game_model.blocker:create({
				name = 'b' .. i,
				field = field,
			})
		end
	end)
end

-- now let's query some stuff to see if our field is ok
print('')
local test_pos = game_model.position:get({ name = '[1:2]'})
print('found position ' .. test_pos.name)
for _, ap in ipairs(test_pos.adjacent) do
	print('adjacent to ' .. ap.name)
end

-- ok now lets play a game

local function get_position(field, r, c)
	return game_model.position:get({
		field_id = field.id,
		name = '[' .. c .. ':' .. r .. ']'
	})
end

local function show_state(field)
	print('')
	local rows = array()
	for r = 1, 7 do
		rows[r] = array()
		for c = 1, 7 do
			rows[r][c] = '  '
			-- find the position object
			local pos = get_position(field, r, c)
			if pos then
				rows[r][c] = '. '
				-- if there is a runner or blocker at this position then show them
				for runner in pos:runners() do
					rows[r][c] = runner.name
				end
				for blocker in pos:blockers() do
					rows[r][c] = blocker.name
				end
			end
		end
		print(table.concat(rows[r], ' ' ))
	end
	-- show which turns are next
	local t = array()
	for _, instance in ipairs(field.turns) do
		t:push(instance.name)
	end
	print(table.concat(t, ' '))
end


for steps = 1, 3 do
	
	-- if the game is finished then reset positions
	if field.state == 'finished' then
		-- reset positions and turns
		game_model:transaction(function ()
			-- field.state = 'game'
			local turns = array()
			local i = 0
			for runner in field:runners() do
				turns:push(runner)
				runner.position = get_position(field, 1, 1 + (i * 2))
				i = i + 1
			end
			i = 0
			for blocker in field:blockers() do
				turns:push(blocker)
				blocker.position = get_position(field, 6, 2 + (i * 4))
				i = i + 1
			end
			field.turns = turns
		end)
		show_state(field)
	end	
		
	-- otherwise see whose turn is next
	-- run AI to pick a move
	-- do the move 
	-- show the board states
	-- process and list consequences
	-- show the board state again if different
	
	
end





print('')
game_model:close()
print('done')