-- Tilemap Flatten
-- Flattens selected tilemap layers into one layer.
--
-- Inputs: tilemap-or-tilemaps, layers, outputLayerName
--   layers: "*", comma-separated layer indexes/names, JSON array, or Lua table.
--           Layers are composited in the provided order: first is bottom,
--           later layers are top and overwrite nonzero cells below.
--   outputLayerName: optional props.name for the resulting layer.
-- Outputs: tilemap-or-tilemaps, stats-or-stats-list

local function fail(message)
	error("tilemap-flatten: " .. message)
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

local function require_integer(value, label)
	local number = tonumber(value)
	if type(number) ~= "number" or number ~= math.floor(number) then
		fail(label .. " must be an integer")
	end
	return number
end

local function require_layers(tilemap, mapLabel)
	local layers = tilemap.layers
	if type(layers) ~= "table" or #layers == 0 then
		fail(mapLabel .. " tilemap.layers must be a non-empty table")
	end
	return layers
end

local function select_layer_index(layers, selector, label)
	local numeric = tonumber(selector)
	if numeric ~= nil then
		local index = require_integer(numeric, label)
		if index < 1 or index > #layers then
			fail(label .. " index out of range: " .. tostring(index))
		end
		return index
	end

	local name = tostring(selector)
	if name == "" then
		fail(label .. " must not be empty")
	end
	for index, layer in ipairs(layers) do
		if type(layer) == "table" and type(layer.props) == "table" and tostring(layer.props.name or "") == name then
			return index
		end
	end
	fail(label .. " name not found: " .. name)
end

local function parse_layer_selectors(tilemap, mapLabel, value)
	local layers = require_layers(tilemap, mapLabel)
	if value == nil or value == "" or tostring(value) == "*" then
		local indexes = {}
		for index = 1, #layers do
			indexes[#indexes + 1] = index
		end
		return indexes
	end

	local rawSelectors = {}
	if type(value) == "table" then
		for _, item in ipairs(value) do
			rawSelectors[#rawSelectors + 1] = item
		end
	elseif type(value) == "string" then
		local text = value:match("^%s*(.-)%s*$")
		local first = text:match("^%s*(.)")
		if first == "[" then
			local ok, decoded = pcall(json.decode, text)
			if not ok or type(decoded) ~= "table" then
				fail("layers JSON array is invalid")
			end
			for _, item in ipairs(decoded) do
				rawSelectors[#rawSelectors + 1] = item
			end
		else
			for part in text:gmatch("[^,]+") do
				rawSelectors[#rawSelectors + 1] = part:match("^%s*(.-)%s*$")
			end
		end
	else
		rawSelectors[#rawSelectors + 1] = value
	end

	if #rawSelectors == 0 then
		fail("layers must contain at least one layer selector")
	end

	local indexes = {}
	for selectorIndex, selector in ipairs(rawSelectors) do
		indexes[#indexes + 1] = select_layer_index(layers, selector, mapLabel .. " layers[" .. tostring(selectorIndex) .. "]")
	end
	return indexes
end

local function validate_layer(layer, mapLabel, index, expectedWidth, expectedLength)
	if type(layer) ~= "table" then
		fail(mapLabel .. " layer " .. tostring(index) .. " must be a table")
	end
	local width = require_integer(layer.width, mapLabel .. " layer " .. tostring(index) .. " width")
	if width <= 0 then
		fail(mapLabel .. " layer " .. tostring(index) .. " width must be greater than zero")
	end
	if type(layer.data) ~= "table" then
		fail(mapLabel .. " layer " .. tostring(index) .. " data must be a table")
	end
	if (#layer.data % width) ~= 0 then
		fail(mapLabel .. " layer " .. tostring(index) .. " data length must be divisible by width")
	end
	if expectedWidth ~= nil and width ~= expectedWidth then
		fail(mapLabel .. " layer " .. tostring(index) .. " width must match bottom layer width")
	end
	if expectedLength ~= nil and #layer.data ~= expectedLength then
		fail(mapLabel .. " layer " .. tostring(index) .. " data length must match bottom layer data length")
	end
	return width, #layer.data
end

local function is_tilemap(value)
	return type(value) == "table" and type(value.layers) == "table"
end

local function apply_to_tilemap(tilemap, mapLabel, layerSelectors, outputLayerName)
	if type(tilemap) ~= "table" then
		fail(mapLabel .. " must be a table")
	end

	local layers = require_layers(tilemap, mapLabel)
	local selectedIndexes = parse_layer_selectors(tilemap, mapLabel, layerSelectors)
	local bottomLayerIndex = selectedIndexes[1]
	local bottomLayer = layers[bottomLayerIndex]
	local width, length = validate_layer(bottomLayer, mapLabel, bottomLayerIndex)

	local outputData = {}
	for tileIndex, tile in ipairs(bottomLayer.data) do
		outputData[tileIndex] = require_integer(tile, mapLabel .. " layer " .. tostring(bottomLayerIndex) .. " data[" .. tostring(tileIndex) .. "]")
	end

	local overwritten = 0
	local written = 0
	for orderIndex = 2, #selectedIndexes do
		local layerIndex = selectedIndexes[orderIndex]
		local layer = layers[layerIndex]
		validate_layer(layer, mapLabel, layerIndex, width, length)
		for tileIndex, tile in ipairs(layer.data) do
			local tileId = require_integer(tile, mapLabel .. " layer " .. tostring(layerIndex) .. " data[" .. tostring(tileIndex) .. "]")
			if tileId ~= 0 then
				if outputData[tileIndex] ~= tileId then
					overwritten = overwritten + 1
				end
				outputData[tileIndex] = tileId
				written = written + 1
			end
		end
	end

	local resultLayer = deep_copy(bottomLayer)
	resultLayer.data = outputData

	if outputLayerName ~= nil and outputLayerName ~= "" then
		if type(resultLayer.props) ~= "table" then
			resultLayer.props = {}
		end
		resultLayer.props.name = tostring(outputLayerName)
	end

	local result = {
		props = deep_copy(tilemap.props or {}),
		layers = { resultLayer },
	}

	return result, {
		layers = selectedIndexes,
		width = width,
		height = length / width,
		written = written,
		overwritten = overwritten,
	}
end

local tilemapInput = inputs[1]
if type(tilemapInput) ~= "table" then
	fail("tilemap input must be a table")
end

if is_tilemap(tilemapInput) then
	local result, stats = apply_to_tilemap(tilemapInput, "tilemap", inputs[2], inputs[3])
	outputs[1] = result
	outputs[2] = stats
else
	local results = {}
	local statsList = {}
	if #tilemapInput == 0 then
		fail("tilemaps input array must not be empty")
	end
	for index, tilemap in ipairs(tilemapInput) do
		local result, stats = apply_to_tilemap(
			tilemap,
			"tilemaps[" .. tostring(index) .. "]",
			inputs[2],
			inputs[3]
		)
		results[index] = result
		statsList[index] = stats
	end
	if #results ~= #tilemapInput then
		fail("tilemaps input must be a dense array of tilemaps")
	end
	outputs[1] = results
	outputs[2] = statsList
end
