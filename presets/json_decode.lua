local function isArray(value)
	if type(value) ~= "table" then
		return false
	end

	local length = 0
	for key, _ in pairs(value) do
		if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
			return false
		end
		if key > length then
			length = key
		end
	end

	for index = 1, length do
		if value[index] == nil then
			return false
		end
	end

	return true
end


local path = inputs[1]
if type(path) == "table" then
	if not isArray(path) then
		error("path input must be a string or array of strings")
	end

	local items = {}
	for index, item in ipairs(path) do
		items[index] = json.decode(item)
	end
	outputs[1] = items
else
	outputs[1] = json.decode(inputs[1])
end