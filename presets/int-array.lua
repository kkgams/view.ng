-- Int Array
-- Creates a fixed-length integer arithmetic sequence.
-- value[index] = start + (index - 1) * increment

local function fail(message)
	error("int-array: " .. message)
end

local function integer(value, label)
	local number = tonumber(value)
	if number == nil or number ~= math.floor(number) then
		fail(label .. " must be an integer")
	end
	return number
end

if not inputs.active[1] then
	fail("length is not connected")
end

local length = integer(inputs[1], "length")
local increment = inputs[2]
local start = inputs[3]

if increment == nil or increment == "" then
	increment = 1
end
if start == nil or start == "" then
	start = 1
end

increment = integer(increment, "increment")
start = integer(start, "start")

if length < 0 then
	fail("length must be greater than or equal to zero")
end

local result = {}
for index = 1, length do
	result[index] = start + (index - 1) * increment
end

outputs[1] = result
