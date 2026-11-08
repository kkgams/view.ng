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

local function deep_copy(value)
	if type(value) ~= "table" then
		return value
	end

	local copied = {}
	for key, item in pairs(value) do
		copied[deep_copy(key)] = deep_copy(item)
	end
	return copied
end

local function flip_layer_y(layer, layerIndex, label)
	if type(layer) ~= "table" then
		error(label .. " layer " .. tostring(layerIndex) .. " must be a table")
	end

	local width = math.floor(tonumber(layer.width) or 0)
	if width <= 0 then
		error(label .. " layer " .. tostring(layerIndex) .. " width must be greater than zero")
	end

	local data = layer.data
	if type(data) ~= "table" then
		error(label .. " layer " .. tostring(layerIndex) .. " data must be a table")
	end
	if (#data % width) ~= 0 then
		error(label .. " layer " .. tostring(layerIndex) .. " data length must be divisible by width")
	end

	local height = #data / width
	local flipped = {}
	for y = 0, height - 1 do
		local sourceY = height - 1 - y
		for x = 0, width - 1 do
			flipped[y * width + x + 1] = data[sourceY * width + x + 1]
		end
	end

	local result = deep_copy(layer)
	result.data = flipped
	return result
end

local function flip_tilemap_y(tilemap, label)
	if tilemap == nil or tilemap == "" then
		error(label .. " is required")
	end
	if type(tilemap) ~= "table" then
		error(label .. " must be a table")
	end

	local layers = tilemap.layers
	if type(layers) ~= "table" then
		error(label .. ".layers must be a table")
	end

	local result = deep_copy(tilemap)
	local resultLayers = deep_copy(layers)
	for index, layer in ipairs(layers) do
		resultLayers[index] = flip_layer_y(layer, index, label)
	end
	result.layers = resultLayers

	return result
end

local tilemap = inputs[1]
if type(tilemap) == "table" and isArray(tilemap) then
	local results = {}
	for index, item in ipairs(tilemap) do
		results[index] = flip_tilemap_y(item, "tilemap[" .. tostring(index) .. "]")
	end
	outputs[1] = results
else
	outputs[1] = flip_tilemap_y(tilemap, "tilemap input")
end
