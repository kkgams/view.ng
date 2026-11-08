-- Tilemap to Collision Segments
-- Converts one tilemap layer into merged exterior collision edge segments.
-- Inputs: map or array of maps, layerIndex, solidTileId, oneWayTileId (optional)
-- Outputs: segments, or array of segment arrays when map input is an array
--
-- Coordinate contract:
-- - tile units
-- - origin at the bottom-left after the tilemap has been FlipY'd
-- - x grows right, y grows up (matching examples/demo/game/world/sys_platformer.odin)
-- - tile row y occupies vertical span [y - 1, y], so row 0 exposes a floor at y = 0
--
-- Segment contract:
-- - each segment is { x1, y1, x2, y2 }
-- - segment_left_normal in sys_platformer.odin must point out of the solid tile area
-- - floors are left-to-right, ceilings are right-to-left, left walls are bottom-to-top,
--   and right walls are top-to-bottom
-- - exterior edges are omitted; only solid-to-playable-empty edges are emitted
-- - "exterior" means any empty tile connected to the tilemap border by empty tiles

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

local function generateSegments(tilemap, layerInput, solidTileInput, oneWayTileInput, label)
	if tilemap == nil or tilemap == "" then
		error(label .. " map is required")
	end

	local layerSelector = tonumber(layerInput) or 1
	if layerSelector < 1 then
		error(label .. " layer index must be 1 or greater")
	end
	layerSelector = math.floor(layerSelector)

	local solidTileId = tonumber(solidTileInput)
	if solidTileId == nil then
		error(label .. " solid tile id is required")
	end
	solidTileId = math.floor(solidTileId)

	local oneWayTileId = nil
	if oneWayTileInput ~= nil and oneWayTileInput ~= "" then
		oneWayTileId = tonumber(oneWayTileInput)
		if oneWayTileId == nil then
			error(label .. " one-way tile id must be numeric when provided")
		end
		oneWayTileId = math.floor(oneWayTileId)
		if oneWayTileId == solidTileId then
			error(label .. " one-way tile id must be different from solid tile id")
		end
	end

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

	local function in_bounds(x, y)
		return x >= 0 and x < width and y >= 0 and y < height
	end

	local function tile_id_at(x, y)
		if not in_bounds(x, y) then
			return nil
		end

		local index = y * width + x + 1
		local tileId = tonumber(data[index])
		if tileId == nil then
			error(label .. " tile id at index " .. tostring(index) .. " is not numeric")
		end

		return math.floor(tileId)
	end

	local function is_solid_at(x, y)
		return tile_id_at(x, y) == solidTileId
	end

	local function is_one_way_at(x, y)
		return oneWayTileId ~= nil and tile_id_at(x, y) == oneWayTileId
	end

	local function is_blocking_at(x, y)
		local tileId = tile_id_at(x, y)
		return tileId == solidTileId or (oneWayTileId ~= nil and tileId == oneWayTileId)
	end

	local exteriorEmpty = {}
	local queue = {}
	local queueHead = 1

	local function cell_index(x, y)
		return y * width + x + 1
	end

	local function enqueue_exterior_empty(x, y)
		if not in_bounds(x, y) or is_blocking_at(x, y) then
			return
		end

		local index = cell_index(x, y)
		if exteriorEmpty[index] then
			return
		end

		exteriorEmpty[index] = true
		queue[#queue + 1] = { x, y }
	end

	for x = 0, width - 1 do
		enqueue_exterior_empty(x, 0)
		enqueue_exterior_empty(x, height - 1)
	end
	for y = 0, height - 1 do
		enqueue_exterior_empty(0, y)
		enqueue_exterior_empty(width - 1, y)
	end

	while queueHead <= #queue do
		local cell = queue[queueHead]
		queueHead = queueHead + 1
		local x = cell[1]
		local y = cell[2]
		enqueue_exterior_empty(x + 1, y)
		enqueue_exterior_empty(x - 1, y)
		enqueue_exterior_empty(x, y + 1)
		enqueue_exterior_empty(x, y - 1)
	end

	local function is_playable_empty_at(x, y)
		return in_bounds(x, y) and not is_blocking_at(x, y) and not exteriorEmpty[cell_index(x, y)]
	end

	local function is_playable_empty_or_one_way_at(x, y)
		return in_bounds(x, y) and not is_solid_at(x, y) and not exteriorEmpty[cell_index(x, y)]
	end

	local segments = {}

	local function add_segment(x1, y1, x2, y2)
		segments[#segments + 1] = { x1, y1, x2, y2 }
	end

	-- Horizontal edges.
	-- Top/floor edges are left-to-right at y; one-way platform tiles only emit these top edges.
	-- Bottom/ceiling edges are right-to-left at y - 1 and are emitted for solid tiles only.
	for y = 0, height - 1 do
		local topStart = nil
		local bottomStart = nil

		for x = 0, width do
			local hasTopEdge = x < width and (is_solid_at(x, y) or is_one_way_at(x, y)) and is_playable_empty_at(x, y + 1)
			local hasBottomEdge = x < width and is_solid_at(x, y) and is_playable_empty_at(x, y - 1)

			if hasTopEdge and topStart == nil then
				topStart = x
			elseif (not hasTopEdge or x == width) and topStart ~= nil then
				add_segment(topStart, y, x, y)
				topStart = nil
			end

			if hasBottomEdge and bottomStart == nil then
				bottomStart = x
			elseif (not hasBottomEdge or x == width) and bottomStart ~= nil then
				add_segment(x, y - 1, bottomStart, y - 1)
				bottomStart = nil
			end
		end
	end

	-- Vertical edges.
	-- Left edges are bottom-to-top; right edges are top-to-bottom.
	-- One-way platform tile bodies are passable from the sides, so solid side edges facing
	-- a one-way platform tile are still emitted.
	for x = 0, width - 1 do
		local leftStart = nil
		local rightStart = nil

		for y = 0, height do
			local hasLeftEdge = y < height and is_solid_at(x, y) and is_playable_empty_or_one_way_at(x - 1, y)
			local hasRightEdge = y < height and is_solid_at(x, y) and is_playable_empty_or_one_way_at(x + 1, y)

			if hasLeftEdge and leftStart == nil then
				leftStart = y
			elseif (not hasLeftEdge or y == height) and leftStart ~= nil then
				add_segment(x, leftStart - 1, x, y - 1)
				leftStart = nil
			end

			if hasRightEdge and rightStart == nil then
				rightStart = y
			elseif (not hasRightEdge or y == height) and rightStart ~= nil then
				add_segment(x + 1, y - 1, x + 1, rightStart - 1)
				rightStart = nil
			end
		end
	end

	return segments
end

local tilemap = inputs[1]
local layerInput = inputs[2]
local solidTileInput = inputs[3]
local oneWayTileInput = inputs[4]

if type(tilemap) == "table" and isArray(tilemap) then
	local segmentLists = {}
	for index, item in ipairs(tilemap) do
		segmentLists[index] = generateSegments(
			item,
			itemAt(layerInput, index),
			itemAt(solidTileInput, index),
			itemAt(oneWayTileInput, index),
			"map[" .. tostring(index) .. "]"
		)
	end
	outputs[1] = segmentLists
else
	outputs[1] = generateSegments(tilemap, layerInput, solidTileInput, oneWayTileInput, "map input")
end
