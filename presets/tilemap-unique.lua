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

local function normalizeTileMaps(input)
	if not isArray(input) then
		return { input }
	end
	return input
end

local function parsePositiveInteger(value, fieldName)
	local number = tonumber(value)

	if number == nil or number <= 0 or number ~= math.floor(number) then
		error(fieldName .. " must be a positive integer")
	end

	return number
end

local function getMapTileSize(tileMap, mapIndex)
	if type(tileMap.props) ~= "table" then
		error("tilemap " .. mapIndex .. " does not define tileSize")
	end

	return parsePositiveInteger(tileMap.props.tileSize, "tilemap " .. mapIndex .. " tileSize")
end

local function getUsedTileIDs(layer, mapIndex, layerIndex)
	if type(layer.data) ~= "table" or not isArray(layer.data) then
		error("tilemap " .. mapIndex .. ", layer " .. layerIndex .. ": data must be an array")
	end

	local width = parsePositiveInteger(layer.width, "tilemap " .. mapIndex .. ", layer " .. layerIndex .. " width")

	if #layer.data % width ~= 0 then
		error(
			"tilemap "
				.. mapIndex
				.. ", layer "
				.. layerIndex
				.. ": data length "
				.. #layer.data
				.. " is not divisible by width "
				.. width
		)
	end

	local seen = {}
	local result = {}

	for dataIndex, rawTileID in ipairs(layer.data) do
		local tileID = tonumber(rawTileID)

		if tileID == nil or tileID < 0 or tileID ~= math.floor(tileID) then
			error(
				"tilemap "
					.. mapIndex
					.. ", layer "
					.. layerIndex
					.. ", data item "
					.. dataIndex
					.. ": tile ID must be a non-negative integer"
			)
		end

		-- Zero means empty.
		if tileID ~= 0 and not seen[tileID] then
			seen[tileID] = true
			result[#result + 1] = tileID
		end
	end

	table.sort(result)

	return result
end

local tileMaps = normalizeTileMaps(inputs[1])

local allLayers = {}

-- Useful for constructing one compact tileset per tile size.
--
-- JSON object keys must normally be strings, so the final keys use
-- tostring(tileSize), for example:
-- {
--     ["16"] = { 1, 2, 7, 19 },
--     ["32"] = { 1, 4, 8 }
-- }
local usedTileIDsBySizeSets = {}

for mapIndex, tileMap in ipairs(tileMaps) do
	if type(tileMap) ~= "table" then
		error("tilemap " .. mapIndex .. " must be a table")
	end

	if type(tileMap.layers) ~= "table" or not isArray(tileMap.layers) then
		error("tilemap " .. mapIndex .. " layers must be an array")
	end

	local tileSize = getMapTileSize(tileMap, mapIndex)
	local tileSizeKey = tostring(tileSize)

	if usedTileIDsBySizeSets[tileSizeKey] == nil then
		usedTileIDsBySizeSets[tileSizeKey] = {}
	end

	local sizeSet = usedTileIDsBySizeSets[tileSizeKey]

	for layerIndex, layer in ipairs(tileMap.layers) do
		if type(layer) ~= "table" then
			error("tilemap " .. mapIndex .. ", layer " .. layerIndex .. " must be a table")
		end

		local usedTileIDs = getUsedTileIDs(layer, mapIndex, layerIndex)

		local outputIndex = #allLayers + 1

		allLayers[outputIndex] = layer

		for _, tileID in ipairs(usedTileIDs) do
			sizeSet[tileID] = true
		end
	end
end

local usedTileIDsBySize = {}

for tileSizeKey, idSet in pairs(usedTileIDsBySizeSets) do
	local ids = {}

	for tileID, _ in pairs(idSet) do
		ids[#ids + 1] = tileID
	end

	table.sort(ids)
	usedTileIDsBySize[tileSizeKey] = ids
end

outputs[1] = allLayers

-- Optional but recommended for the next pipeline stage.
outputs[2] = usedTileIDsBySize
