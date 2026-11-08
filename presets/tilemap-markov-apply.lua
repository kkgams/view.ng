-- Apply a MarkovJunior model to a tilemap layer using direct 1:1 ids.
--
-- Contract:
--   tile id N == Markov value index N
--
-- The model author owns the meaning and order of the model's `values` string.
-- For example, if a model declares values="XBSEP", then tile id 0 means X,
-- tile id 1 means B, tile id 2 means S, and so on. Locked/outside behavior is
-- model-owned: use a symbol such as X and avoid rules that rewrite it.
--
-- Inputs: tilemap-or-tilemaps, layer, modelIrPath, seed, maxSteps
-- Outputs: tilemap-or-tilemaps, grid-or-grids, stats-or-stats-list

local function fail(message)
	error("tilemap-markov-apply: " .. message)
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

local function optional_integer(value, label, default)
	if value == nil or value == "" then
		return default
	end
	return require_integer(value, label)
end

local function select_layer(tilemap, selector)
	local layers = tilemap.layers
	if type(layers) ~= "table" then
		fail("tilemap.layers must be a table")
	end

	if selector == nil or selector == "" then
		selector = 1
	end

	local numeric = tonumber(selector)
	if numeric ~= nil then
		local index = require_integer(numeric, "layer")
		if index < 1 or index > #layers then
			fail("layer index out of range: " .. tostring(index))
		end
		return index, layers[index]
	end

	local name = tostring(selector)
	for index, layer in ipairs(layers) do
		if type(layer) == "table" and type(layer.props) == "table" and tostring(layer.props.name or "") == name then
			return index, layer
		end
	end
	fail("layer name not found: " .. name)
end

local function read_le_u32(bytes, offset, label)
	local b0 = bytes[offset]
	local b1 = bytes[offset + 1]
	local b2 = bytes[offset + 2]
	local b3 = bytes[offset + 3]
	if b0 == nil or b1 == nil or b2 == nil or b3 == nil then
		fail(label .. " is missing from modelIr")
	end
	return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216
end

local function read_model_ir(path)
	local text = host.call("fs/fs::read-text", path)
	local bytes = json.decode(text)
	if type(bytes) ~= "table" then
		fail("modelIrPath must decode to a JSON byte array")
	end
	for index, byte in ipairs(bytes) do
		if type(byte) ~= "number" or byte ~= math.floor(byte) or byte < 0 or byte > 255 then
			fail("modelIr byte " .. tostring(index) .. " must be an integer in 0..255")
		end
	end
	if bytes[1] ~= 77 or bytes[2] ~= 74 or bytes[3] ~= 73 or bytes[4] ~= 82 then
		fail("modelIr must start with MJIR magic bytes")
	end
	local valueCount = read_le_u32(bytes, 9, "modelIr value count")
	if valueCount <= 0 then
		fail("modelIr value count must be greater than zero")
	end
	return bytes, valueCount
end

local function is_tilemap(value)
	return type(value) == "table" and type(value.layers) == "table"
end

local function describe_tilemap(tilemap, fallbackLabel)
	local parts = { fallbackLabel }
	local props = tilemap.props
	if type(props) == "table" then
		local roomId = props["gams.room.id"]
		if roomId ~= nil and roomId ~= "" then
			parts[#parts + 1] = "room " .. tostring(roomId)
		end
		local name = props.name or props["gams.room.name"]
		if name ~= nil and name ~= "" then
			parts[#parts + 1] = "name " .. tostring(name)
		end
	end
	return table.concat(parts, " / ")
end

local function apply_to_tilemap(tilemap, mapLabel, layerSelector, modelIr, modelValueCount, seed, maxSteps)
	if type(tilemap) ~= "table" then
		fail(mapLabel .. " must be a table")
	end

	mapLabel = describe_tilemap(tilemap, mapLabel)

	local layerIndex, layer = select_layer(tilemap, layerSelector)
	if type(layer) ~= "table" then
		fail(mapLabel .. " selected layer must be a table")
	end

	local width = require_integer(layer.width, mapLabel .. " layer.width")
	if width <= 0 then
		fail(mapLabel .. " layer.width must be greater than zero")
	end
	if type(layer.data) ~= "table" then
		fail(mapLabel .. " selected layer.data must be a table")
	end
	if (#layer.data % width) ~= 0 then
		fail(mapLabel .. " selected layer.data length must be divisible by layer.width")
	end
	local height = #layer.data / width
	if height <= 0 then
		fail(mapLabel .. " selected layer height must be greater than zero")
	end

	local cells = {}
	local tileCounts = {}
	for index, tile in ipairs(layer.data) do
		local tileId = require_integer(tile, mapLabel .. " layer.data[" .. tostring(index) .. "]")
		if tileId < 0 or tileId > 255 then
			fail(mapLabel .. " tile id " .. tostring(tileId) .. " must be in 0..255 for Markov cells")
		end
		if tileId >= modelValueCount then
			local zeroBased = index - 1
			local x = zeroBased % width
			local y = math.floor(zeroBased / width)
			fail(
				mapLabel
					.. " layer "
					.. tostring(layerIndex)
					.. " tile id "
					.. tostring(tileId)
					.. " at layer.data["
					.. tostring(index)
					.. "] (x="
					.. tostring(x)
					.. ", y="
					.. tostring(y)
					.. ") is outside the Markov model value range 0.."
					.. tostring(modelValueCount - 1)
			)
		end
		cells[index] = tileId
		local tileCountKey = tostring(tileId)
		tileCounts[tileCountKey] = (tileCounts[tileCountKey] or 0) + 1
	end

	local grid = host.call("markov-junior/markov-junior::run", modelIr, cells, {
		width = width,
		height = height,
		depth = 1,
		seed = seed,
		["max-steps"] = maxSteps,
	})

	if type(grid) ~= "table" then
		fail(mapLabel .. " markov-junior returned non-table grid")
	end
	if type(grid.cells) ~= "table" then
		fail(mapLabel .. " markov-junior grid.cells must be a table")
	end
	if #grid.cells ~= width * height then
		fail(mapLabel .. " markov-junior grid.cells length does not match tilemap layer size")
	end
	local outputData = {}
	local changed = 0
	for index, cell in ipairs(grid.cells) do
		if type(cell) ~= "number" or cell ~= math.floor(cell) or cell < 0 or cell > 255 then
			fail(mapLabel .. " markov-junior cell " .. tostring(index) .. " must be an integer in 0..255")
		end
		outputData[index] = cell
		if cell ~= layer.data[index] then
			changed = changed + 1
		end
	end

	local result = deep_copy(tilemap)
	result.layers[layerIndex] = deep_copy(result.layers[layerIndex])
	result.layers[layerIndex].data = outputData

	return result, grid, {
		width = width,
		height = height,
		values = grid.values,
		seed = seed,
		maxSteps = maxSteps,
		stepsRun = grid["steps-run"],
		changed = grid.changed,
		done = grid.done,
		writtenCellsChanged = changed,
		tileCounts = tileCounts,
	}
end

local tilemapInput = inputs[1]
if type(tilemapInput) ~= "table" then
	fail("tilemap input must be a table")
end

local modelIrPath = tostring(inputs[3] or "")
if modelIrPath == "" then
	fail("modelIrPath must be non-empty")
end
local seed = optional_integer(inputs[4], "seed", 1)
local maxSteps = optional_integer(inputs[5], "maxSteps", 10000)
local modelIr, modelValueCount = read_model_ir(modelIrPath)

if is_tilemap(tilemapInput) then
	local result, grid, stats = apply_to_tilemap(tilemapInput, "tilemap", inputs[2], modelIr, modelValueCount, seed, maxSteps)
	outputs[1] = result
	outputs[2] = grid
	outputs[3] = stats
else
	local results = {}
	local grids = {}
	local statsList = {}
	if #tilemapInput == 0 then
		fail("tilemaps input array must not be empty")
	end
	for index, tilemap in ipairs(tilemapInput) do
		local result, grid, stats = apply_to_tilemap(
			tilemap,
			"tilemaps[" .. tostring(index) .. "]",
			inputs[2],
			modelIr,
			modelValueCount,
			seed,
			maxSteps
		)
		results[index] = result
		grids[index] = grid
		statsList[index] = stats
	end
	if #results ~= #tilemapInput then
		fail("tilemaps input must be a dense array of tilemaps")
	end
	outputs[1] = results
	outputs[2] = grids
	outputs[3] = statsList
end
