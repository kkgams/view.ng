-- Array Length
-- Returns the number of items in a dense one-based array.

if not inputs.active[1] then
	error("array is not connected")
end

local array = inputs[1]
if type(array) ~= "table" then
	error("array must be an array")
end

local length = 0
for key, _ in pairs(array) do
	if type(key) ~= "number" or key ~= math.floor(key) or key < 1 then
		error("array must contain only positive integer keys")
	end
	if key > length then
		length = key
	end
end

for index = 1, length do
	if array[index] == nil then
		error("array item '" .. tostring(index) .. "' is nil")
	end
end

outputs[1] = length
