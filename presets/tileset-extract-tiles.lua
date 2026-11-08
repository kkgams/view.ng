-- Extract Tileset Tiles
-- Builds a compact, near-square tileset from selected global, 1-based tile IDs.
-- Source tilesets occupy consecutive global ID ranges in input order.
-- Requested tiles retain their input order in the output tileset.

local function fail(message)
	error("tileset-extract-tiles: " .. message)
end

local function array_length(value, label)
	if type(value) ~= "table" then
		fail(label .. " must be an array")
	end

	local length = 0
	for key, _ in pairs(value) do
		if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
			fail(label .. " must contain only positive integer keys")
		end
		if key > length then
			length = key
		end
	end

	for index = 1, length do
		if value[index] == nil then
			fail(label .. " must be a dense array; item " .. tostring(index) .. " is missing")
		end
	end

	return length
end

local function positive_integer(value, label)
	local number = tonumber(value)
	if number == nil or number <= 0 or number ~= math.floor(number) then
		fail(label .. " must be a positive integer")
	end
	return number
end

if not inputs.active[1] then
	fail("tilesets is not connected")
end
if not inputs.active[2] then
	fail("tileSize is not connected")
end
if not inputs.active[3] then
	fail("tileIDs is not connected")
end

local tilesets = inputs[1]
local tileSize = positive_integer(inputs[2], "tileSize")
local tileIDs = inputs[3]
local tilesetCount = array_length(tilesets, "tilesets")
local requestedCount = array_length(tileIDs, "tileIDs")

if tilesetCount == 0 then
	fail("tilesets must contain at least one image")
end
if requestedCount == 0 then
	fail("tileIDs must contain at least one tile ID")
end

local sources = {}
local totalTileCount = 0
for index = 1, tilesetCount do
	local image = tilesets[index]
	local info = host.call("image/image::info", image)
	if type(info) ~= "table" then
		fail("tilesets[" .. tostring(index) .. "] info must be a table")
	end

	local width = positive_integer(info.width, "tilesets[" .. tostring(index) .. "] width")
	local height = positive_integer(info.height, "tilesets[" .. tostring(index) .. "] height")
	if width % tileSize ~= 0 or height % tileSize ~= 0 then
		fail(
			"tilesets["
				.. tostring(index)
				.. "] dimensions "
				.. tostring(width)
				.. "x"
				.. tostring(height)
				.. " must both be divisible by tileSize "
				.. tostring(tileSize)
		)
	end

	local columns = width / tileSize
	local tileCount = columns * (height / tileSize)
	sources[index] = {
		image = image,
		columns = columns,
		firstID = totalTileCount + 1,
		lastID = totalTileCount + tileCount,
	}
	totalTileCount = totalTileCount + tileCount
end

local columns = math.ceil(math.sqrt(requestedCount))
local rows = math.ceil(requestedCount / columns)
local output = host.call("image/image::create", columns * tileSize, rows * tileSize, json.null)

for outputIndex = 1, requestedCount do
	local globalID = positive_integer(tileIDs[outputIndex], "tileIDs[" .. tostring(outputIndex) .. "]")
	if globalID > totalTileCount then
		fail(
			"tileIDs["
				.. tostring(outputIndex)
				.. "] "
				.. tostring(globalID)
				.. " exceeds available global tile range 1-"
				.. tostring(totalTileCount)
		)
	end

	local source = nil
	for sourceIndex = 1, tilesetCount do
		if globalID <= sources[sourceIndex].lastID then
			source = sources[sourceIndex]
			break
		end
	end

	local localZeroBasedID = globalID - source.firstID
	local sourceX = (localZeroBasedID % source.columns) * tileSize
	local sourceY = math.floor(localZeroBasedID / source.columns) * tileSize
	local tile = host.call("image/image::crop", source.image, {
		x0 = sourceX,
		y0 = sourceY,
		x1 = sourceX + tileSize,
		y1 = sourceY + tileSize,
	})

	local outputZeroBasedIndex = outputIndex - 1
	output = host.call("image/image::blit", output, tile, {
		x = (outputZeroBasedIndex % columns) * tileSize,
		y = math.floor(outputZeroBasedIndex / columns) * tileSize,
	})
end

outputs[1] = output
