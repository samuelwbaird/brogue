-- reference the brogue libraries
package.path = '../source/?.lua;' .. package.path

-- demonstrate the light and loose ORM model
--
-- this demonstration introduces the grid and turn based game of runners and blockers
-- the runners must reach the other end of the field, the blockers must prevent them
-- the game is modelled using the dweeb ORM and changes are persisted to a database
-- each time this script is run the game continues for a few more steps
-- demonstrating the persistence of data
--
-- the rules
-- the game runs on a 7x7 grid, runners start at one end, blockers in the other half
-- there are 4 runners and two blockers
-- the runners move first, one at a time, then the blockers
-- runners may stay still or move to an unoccupied adjacent square
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
	
		field:create_all_positions()

		-- we can access the collection, with parameter of true to fetch the entire collection into an array
		print('field has ' .. #field:positions(true) .. ' positions')

		-- now let's query some stuff to see if our field is ok
		print('')
		local test_pos = game_model.position:get({ name = '[1:2]'})
		print('test position ' .. test_pos.name)
		for _, ap in ipairs(test_pos.adjacent) do
			print('adjacent to ' .. ap.name)
		end
	end)
end

-- ok now lets play a few more steps of the game, picking up from wherever we left off

for steps = 1, 3 do
	print('')
	
	-- if the game is finished then reset positions
	if field.state == 'finished' then
		-- reset positions and turns
		game_model:transaction(function ()
			field:reset()
			field.state = 'game'
		end)
		print(':reset')
		print(field:display())
		
		
	elseif field.state == 'game' then
		local next = field.turns[1]
		local move = next:get_move()
		print(next.name .. ' -> ' .. (move and move.name or 'no move'))
		
		game_model:transaction(function ()
			-- apply the move
			if move then
				next.position = move
				-- check for consequences
				if next.class_name == 'runner' then
					if move.row == 7 then
						print(next.name .. ' made it to the end')
						print('runners win')
						field.state = 'finished'
					end
				elseif next.class_name == 'blocker' then
					for _, ar in ipairs(move:adjacent_runners()) do
						print(next.name .. ' tagged ' .. ar.name)
						if field:remove_runner(ar) then
							print('blockers win')
							field.state = 'finished'
						end
					end
				end
			end
			
			-- update the turns
			field:shift_turns()
		end)
		print(field:display())
		
		if field.state == 'finished' then
			break
		end
		
	end	
end

print('')
game_model:close()
print('done')