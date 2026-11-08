local tilemap = inputs[1]
if tilemap == nil or tilemap == "" then
	error("tilemap input is required")
end
if type(tilemap) ~= "table" then
	error("tilemap input must be a table")
end

local layerIndex = tonumber(inputs[2]) or 1
if layerIndex < 1 then
	error("layer index must be 1 or greater")
end
layerIndex = math.floor(layerIndex)

local layers = tilemap.layers
if type(layers) ~= "table" or #layers == 0 then
	error("tilemap.layers must be a non-empty table")
end

local sourceLayer = layers[layerIndex]
if type(sourceLayer) ~= "table" then
	error("layer not found at index " .. tostring(layerIndex))
end

local sourceWidth = math.floor(tonumber(sourceLayer.width) or 0)
if sourceWidth <= 0 then
	error("source layer width must be greater than zero")
end

local sourceData = sourceLayer.data
if type(sourceData) ~= "table" then
	error("source layer data must be a table")
end
if (#sourceData % sourceWidth) ~= 0 then
	error("source layer data length must be divisible by width")
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

local seen = {}
local tileIds = {}
for index, tile in ipairs(sourceData) do
	local tileId = tonumber(tile)
	if tileId == nil then
		error("source layer tile " .. tostring(index) .. " must be numeric")
	end
	if tileId > 0 and seen[tileId] == nil then
		seen[tileId] = true
		tileIds[#tileIds + 1] = tileId
	end
end
table.sort(tileIds)

for layerIndexToCheck, layer in ipairs(layers) do
	if type(layer) ~= "table" then
		error("tilemap layer " .. tostring(layerIndexToCheck) .. " must be a table")
	end
	local width = math.floor(tonumber(layer.width) or 0)
	if width ~= sourceWidth then
		error("tilemap layer " .. tostring(layerIndexToCheck) .. " width must match source layer width")
	end
	if type(layer.data) ~= "table" then
		error("tilemap layer " .. tostring(layerIndexToCheck) .. " data must be a table")
	end
	if #layer.data ~= #sourceData then
		error("tilemap layer " .. tostring(layerIndexToCheck) .. " data length must match source layer data length")
	end
end

local rooms = {}
for _, tileId in ipairs(tileIds) do
	local room = deep_copy(tilemap)
	room.layers = {}

	local props = deep_copy(tilemap.props or {})
	props["gams.room.id"] = tostring(tileId)
	props["gams.room.sourceLayerIndex"] = tostring(layerIndex)
	room.props = props

	for currentLayerIndex, layer in ipairs(layers) do
		local roomLayer = deep_copy(layer)
		local roomData = {}
		for tileIndex, tile in ipairs(layer.data) do
			if tonumber(sourceData[tileIndex]) == tileId then
				roomData[tileIndex] = tile
			else
				roomData[tileIndex] = 0
			end
		end
		roomLayer.data = roomData
		room.layers[currentLayerIndex] = roomLayer
	end

	rooms[#rooms + 1] = room
end

outputs[1] = rooms
