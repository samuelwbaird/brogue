-- test the many to many collection

-- reference the brogue libraries
package.path = '../source/?.lua;' .. package.path

local mtm = require('core.mtm')

local test1 = mtm(false)
local test2 = mtm(true)

-- stop garbage collection while populating the test data
-- garbage.stop()

for i = 1, 1000 do
	local key = math.random(1, 100)
	local value = math.random(1, 100)
	test1:set({ key }, value)
	test2:set(key, value)
end


print('')
test1:get(10):with_each(function (value)
	print(value)
end)

print('')
test2:get(10):with_each(function (value)
	print(value)
end)

test1:remove(21)
test2:remove(21)

print('')
test1:pull(10):with_each(function (value)
	print(value)
end)

print('')
test2:pull(10):with_each(function (value)
	print(value)
end)

print('')
test1:pull(10):with_each(function (value)
	print(value)
end)

-- print('')
-- test1:pull(10):with_each(function (value)
-- 	print(value)
-- end)
-- 
-- 
-- print('')
-- test2:pull(10):with_each(function (value)
-- 	print(value)
-- end)
-- 
