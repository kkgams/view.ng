-- Array At
-- Returns the item at an index in a dense array.
-- Positive indexes are one-based; negative indexes count backward from the end.
-- For example, 1 is the first item and -1 is the last item.
-- Zero is invalid. The output is inactive when the index is out of range.

if not inputs.active[1] then
	error("array is not connected")
end
if not inputs.active[2] then
	error("index is not connected")
end

local array = inputs[1]
local index = inputs[2]

if type(array) ~= "table" then
	error("array must be an array")
end
if type(index) ~= "number" or index ~= math.floor(index) or index == 0 then
	error("index must be a non-zero integer")
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

for itemIndex = 1, length do
	if array[itemIndex] == nil then
		error("array item '" .. tostring(itemIndex) .. "' is nil")
	end
end

local resolvedIndex = index
if index < 0 then
	resolvedIndex = length + index + 1
end

if resolvedIndex < 1 or resolvedIndex > length then
	outputs.active[1] = false
else
	outputs[1] = array[resolvedIndex]
end
