local array = inputs[1]
if not inputs.active[1] then
	error("array is not connected")
end
if array == nil then
	error("array is nil")
end
if type(array) ~= "table" then
	error("array must be a table")
end

local count = 0
for key, _ in pairs(array) do
	if type(key) ~= "number" or key ~= math.floor(key) or key < 1 then
		error("array must contain only positive integer keys")
	end
	if key > count then
		count = key
	end
end

for index = 1, count do
	if array[index] == nil then
		error("array item '" .. index .. "' is nil")
	end
end

local outputIds = {}
for key, _ in pairs(outputs.active) do
	if type(key) == "number" then
		outputIds[#outputIds + 1] = key
	end
end
table.sort(outputIds)

for outputIndex, outputId in ipairs(outputIds) do
	if outputIndex <= count then
		outputs[outputId] = array[outputIndex]
	else
		outputs.active[outputId] = false
	end
end
