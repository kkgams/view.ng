-- Tilemap Find Tile Positions
-- Finds every occurrence of one tile id in one tilemap layer.
-- Inputs: map or array of maps, layerIndex, tileId
-- Outputs: positions, or array of position arrays when map input is an array
--
-- Coordinate contract:
-- - zero-based integer tile coordinates: { x, y }
-- - coordinates reflect the input tilemap exactly
-- - run after tilemap-flipy.lua for a bottom-left origin with y growing up
-- - no tile-size scaling or anchor offset is applied
-- - positions are emitted in row-major order

local function is_array(value)
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

local function item_at(value, index)
	if type(value) == "table" and is_array(value) then
		return value[index]
	end
	return value
end

local function require_integer(value, label)
	local number = tonumber(value)
	if number == nil or number ~= math.floor(number) then
		error(label .. " must be an integer")
	end
	return number
end

local function find_positions(tilemap, layer_input, tile_input, label)
	if tilemap == nil or tilemap == "" then
		error(label .. " map is required")
	end
	if type(tilemap) ~= "table" then
		error(label .. " map must be a table")
	end

	local layer_index = 1
	if layer_input ~= nil and layer_input ~= "" then
		layer_index = require_integer(layer_input, label .. " layer index")
	end
	if layer_index < 1 then
		error(label .. " layer index must be 1 or greater")
	end

	local target_tile_id = require_integer(tile_input, label .. " tile id")

	local layers = tilemap.layers
	if type(layers) ~= "table" or #layers == 0 then
		error(label .. " tilemap has no layers")
	end

	local layer = layers[layer_index]
	if type(layer) ~= "table" then
		error(label .. " layer not found at index " .. tostring(layer_index))
	end

	local width = require_integer(layer.width, label .. " layer width")
	if width <= 0 then
		error(label .. " layer width must be greater than zero")
	end

	local data = layer.data
	if type(data) ~= "table" then
		error(label .. " layer data is missing")
	end
	if #data == 0 or (#data % width) ~= 0 then
		error(label .. " invalid layer dimensions")
	end

	local positions = {}
	for index, raw_tile_id in ipairs(data) do
		local tile_id = require_integer(raw_tile_id, label .. " tile id at index " .. tostring(index))
		if tile_id == target_tile_id then
			local zero_based_index = index - 1
			positions[#positions + 1] = {
				zero_based_index % width,
				math.floor(zero_based_index / width),
			}
		end
	end

	return positions
end

local tilemap = inputs[1]
local layer_input = inputs[2]
local tile_input = inputs[3]

if type(tilemap) == "table" and is_array(tilemap) then
	local position_lists = {}
	for index, item in ipairs(tilemap) do
		position_lists[index] = find_positions(
			item,
			item_at(layer_input, index),
			item_at(tile_input, index),
			"map[" .. tostring(index) .. "]"
		)
	end
	outputs[1] = position_lists
else
	outputs[1] = find_positions(tilemap, layer_input, tile_input, "map input")
end
