-- Tilemap to AABBs
-- Converts selected tiles from one tilemap layer into an exact rectangle cover.
-- Inputs: map or array of maps, layerIndex, tileId
-- Outputs: aabbs, or array of AABB arrays when map input is an array
--
-- Coordinate contract:
-- - tile units
-- - origin at the bottom-left after the tilemap has been FlipY'd
-- - x grows right, y grows up
-- - tile row y occupies vertical span [y - 1, y], matching tilemap-to-segments.lua
--
-- AABB contract:
-- - each AABB is { min_x, min_y, max_x, max_y }
-- - output uses array shape: { x1, y1, x2, y2 }
-- - rectangles preserve the exact selected-tile shape; empty cells are never covered

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

local function itemAt(value, index)
	if type(value) == "table" and isArray(value) then
		return value[index]
	end
	return value
end

local function generateAabbs(tilemap, layerInput, tileInput, label)
	if tilemap == nil or tilemap == "" then
		error(label .. " map is required")
	end
	if type(tilemap) ~= "table" then
		error(label .. " map must be a table")
	end

	local layerSelector = tonumber(layerInput) or 1
	if layerSelector < 1 then
		error(label .. " layer index must be 1 or greater")
	end
	layerSelector = math.floor(layerSelector)

	local targetTileId = tonumber(tileInput)
	if targetTileId == nil then
		error(label .. " tile id is required")
	end
	targetTileId = math.floor(targetTileId)

	local layers = tilemap.layers
	if type(layers) ~= "table" or #layers == 0 then
		error(label .. " tilemap has no layers")
	end

	local layer = layers[layerSelector]
	if type(layer) ~= "table" then
		error(label .. " layer not found at index " .. tostring(layerSelector))
	end

	local width = math.floor(tonumber(layer.width) or 0)
	local data = layer.data
	if type(data) ~= "table" then
		error(label .. " layer data is missing")
	end

	if width <= 0 or (#data % width) ~= 0 then
		error(label .. " invalid layer dimensions")
	end

	local height = #data / width
	if height <= 0 then
		error(label .. " invalid layer dimensions")
	end

	local function cellIndex(x, y)
		return y * width + x + 1
	end

	local function isTargetAt(x, y)
		local index = cellIndex(x, y)
		local tileId = tonumber(data[index])
		if tileId == nil then
			error(label .. " tile id at index " .. tostring(index) .. " is not numeric")
		end
		return math.floor(tileId) == targetTileId
	end

	local visited = {}
	local aabbs = {}

	local function isAvailableAt(x, y)
		return isTargetAt(x, y) and not visited[cellIndex(x, y)]
	end

	local function markVisited(minX, minY, maxX, maxY)
		for y = minY, maxY - 1 do
			for x = minX, maxX - 1 do
				visited[cellIndex(x, y)] = true
			end
		end
	end

	for y = 0, height - 1 do
		for x = 0, width - 1 do
			if isAvailableAt(x, y) then
				local rectWidth = 1
				while x + rectWidth < width and isAvailableAt(x + rectWidth, y) do
					rectWidth = rectWidth + 1
				end

				local rectHeight = 1
				local canGrow = true
				while y + rectHeight < height and canGrow do
					for rectX = x, x + rectWidth - 1 do
						if not isAvailableAt(rectX, y + rectHeight) then
							canGrow = false
							break
						end
					end
					if canGrow then
						rectHeight = rectHeight + 1
					end
				end

				markVisited(x, y, x + rectWidth, y + rectHeight)
				aabbs[#aabbs + 1] = { x, y - 1, x + rectWidth, y + rectHeight - 1 }
			end
		end
	end

	return aabbs
end

local tilemap = inputs[1]
local layerInput = inputs[2]
local tileInput = inputs[3]

if type(tilemap) == "table" and isArray(tilemap) then
	local aabbLists = {}
	for index, item in ipairs(tilemap) do
		aabbLists[index] = generateAabbs(
			item,
			itemAt(layerInput, index),
			itemAt(tileInput, index),
			"map[" .. tostring(index) .. "]"
		)
	end
	outputs[1] = aabbLists
else
	outputs[1] = generateAabbs(tilemap, layerInput, tileInput, "map input")
end
