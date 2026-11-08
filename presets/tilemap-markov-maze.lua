-- Generate a simple MarkovJunior maze into a tilemap layer.
-- Inputs: tilemap, layer, seed, maxSteps, wallTile, floorTile, modelIrPath
-- Outputs: tilemap, grid, stats

local function fail(message)
	error("tilemap-markov-maze: " .. message)
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
	return bytes
end

local tilemap = inputs[1]
if type(tilemap) ~= "table" then
	fail("tilemap input must be a table")
end

local layerIndex, layer = select_layer(tilemap, inputs[2])
if type(layer) ~= "table" then
	fail("selected layer must be a table")
end

local width = require_integer(layer.width, "layer.width")
if width <= 0 then
	fail("layer.width must be greater than zero")
end
if type(layer.data) ~= "table" then
	fail("selected layer.data must be a table")
end
if (#layer.data % width) ~= 0 then
	fail("selected layer.data length must be divisible by layer.width")
end
local height = #layer.data / width
if height <= 0 then
	fail("selected layer height must be greater than zero")
end

local seed = optional_integer(inputs[3], "seed", 1)
local maxSteps = optional_integer(inputs[4], "maxSteps", 10000)
local wallTile = optional_integer(inputs[5], "wallTile", 1)
local floorTile = optional_integer(inputs[6], "floorTile", 0)
local modelIrPath = tostring(inputs[7] or "ng/markov/masked-maze-growth.mjir.json")
if modelIrPath == "" then
	fail("modelIrPath must be non-empty")
end

local minX = width
local minY = height
local maxX = -1
local maxY = -1
local maskCount = 0
for y = 0, height - 1 do
	for x = 0, width - 1 do
		local index = y * width + x + 1
		if layer.data[index] == wallTile then
			if x < minX then minX = x end
			if y < minY then minY = y end
			if x > maxX then maxX = x end
			if y > maxY then maxY = y end
			maskCount = maskCount + 1
		end
	end
end
if maskCount == 0 then
	fail("selected layer contains no wallTile/mask tiles: " .. tostring(wallTile))
end

local cells = {}
for index = 1, width * height do
	if layer.data[index] == wallTile then
		cells[index] = 1 -- B: mutable maze wall/mask
	else
		cells[index] = 0 -- X: locked outside/non-mask tile
	end
end

local targetX = math.floor((minX + maxX) / 2)
local targetY = math.floor((minY + maxY) / 2)
local originIndex = 0
local originDistance = nil
for y = 0, height - 1 do
	for x = 0, width - 1 do
		local index = y * width + x + 1
		if layer.data[index] == wallTile then
			local dx = x - targetX
			local dy = y - targetY
			local distance = dx * dx + dy * dy
			if originDistance == nil or distance < originDistance then
				originDistance = distance
				originIndex = index
			end
		end
	end
end
if originIndex <= 0 then
	fail("could not choose Markov origin inside mask")
end
cells[originIndex] = 2 -- W: origin corridor/head

local grid = host.call(
	"markov-junior/markov-junior::run",
	read_model_ir(modelIrPath),
	cells,
	{
		width = width,
		height = height,
		depth = 1,
		seed = seed,
		["max-steps"] = maxSteps,
	}
)

if type(grid) ~= "table" then
	fail("markov-junior returned non-table grid")
end
if type(grid.cells) ~= "table" then
	fail("markov-junior grid.cells must be a table")
end
if #grid.cells ~= width * height then
	fail("markov-junior grid.cells length does not match tilemap layer size")
end
if grid.values ~= "XBWA" then
	fail("expected masked MazeGrowth grid values XBWA, got " .. tostring(grid.values))
end

local symbolToTile = {
	B = wallTile,
	W = floorTile,
	A = floorTile,
}

local outputData = deep_copy(layer.data)
for index, cell in ipairs(grid.cells) do
	if layer.data[index] == wallTile then
		if type(cell) ~= "number" or cell ~= math.floor(cell) then
			fail("markov-junior cell " .. tostring(index) .. " must be an integer")
		end
		local symbol = string.sub(grid.values, cell + 1, cell + 1)
		local tile = symbolToTile[symbol]
		if tile == nil then
			fail("no tile mapping for mutable Markov symbol " .. tostring(symbol))
		end
		outputData[index] = tile
	end
end

local result = deep_copy(tilemap)
result.layers[layerIndex] = deep_copy(result.layers[layerIndex])
result.layers[layerIndex].data = outputData

outputs[1] = result
outputs[2] = grid
outputs[3] = {
	width = width,
	height = height,
	runWidth = width,
	runHeight = height,
	maskCount = maskCount,
	seed = seed,
	maxSteps = maxSteps,
	stepsRun = grid["steps-run"],
	changed = grid.changed,
	done = grid.done,
}
