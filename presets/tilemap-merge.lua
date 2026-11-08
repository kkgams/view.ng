local rooms = inputs[1]
if rooms == nil or rooms == "" then
	error("rooms input is required")
end
if type(rooms) ~= "table" then
	error("rooms input must be a table")
end
if #rooms == 0 then
	error("rooms input must contain at least one tilemap")
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

local first = rooms[1]
if type(first) ~= "table" then
	error("room 1 must be a tilemap table")
end
if type(first.layers) ~= "table" or #first.layers == 0 then
	error("room 1 layers must be a non-empty table")
end

local layerCount = #first.layers
local layerWidths = {}
local layerLengths = {}

for layerIndex, layer in ipairs(first.layers) do
	if type(layer) ~= "table" then
		error("room 1 layer " .. tostring(layerIndex) .. " must be a table")
	end
	local width = math.floor(tonumber(layer.width) or 0)
	if width <= 0 then
		error("room 1 layer " .. tostring(layerIndex) .. " width must be greater than zero")
	end
	if type(layer.data) ~= "table" then
		error("room 1 layer " .. tostring(layerIndex) .. " data must be a table")
	end
	if (#layer.data % width) ~= 0 then
		error("room 1 layer " .. tostring(layerIndex) .. " data length must be divisible by width")
	end
	layerWidths[layerIndex] = width
	layerLengths[layerIndex] = #layer.data
end

local result = {
	layers = {},
}
local resultProps = deep_copy(first.props or {})
resultProps["gams.room.id"] = nil
resultProps["gams.room.sourceLayerIndex"] = nil
if next(resultProps) ~= nil then
	result.props = resultProps
end

for layerIndex, sourceLayer in ipairs(first.layers) do
	local resultLayer = deep_copy(sourceLayer)
	local data = {}
	for tileIndex = 1, layerLengths[layerIndex] do
		data[tileIndex] = 0
	end
	resultLayer.data = data
	result.layers[layerIndex] = resultLayer
end

for roomIndex, room in ipairs(rooms) do
	if type(room) ~= "table" then
		error("room " .. tostring(roomIndex) .. " must be a tilemap table")
	end
	if type(room.layers) ~= "table" then
		error("room " .. tostring(roomIndex) .. " layers must be a table")
	end
	if #room.layers ~= layerCount then
		error("room " .. tostring(roomIndex) .. " layer count must match room 1")
	end

	for layerIndex, layer in ipairs(room.layers) do
		if type(layer) ~= "table" then
			error("room " .. tostring(roomIndex) .. " layer " .. tostring(layerIndex) .. " must be a table")
		end
		local width = math.floor(tonumber(layer.width) or 0)
		if width ~= layerWidths[layerIndex] then
			error("room " .. tostring(roomIndex) .. " layer " .. tostring(layerIndex) .. " width must match room 1")
		end
		if type(layer.data) ~= "table" then
			error("room " .. tostring(roomIndex) .. " layer " .. tostring(layerIndex) .. " data must be a table")
		end
		if #layer.data ~= layerLengths[layerIndex] then
			error(
				"room " .. tostring(roomIndex) .. " layer " .. tostring(layerIndex) .. " data length must match room 1"
			)
		end

		local resultData = result.layers[layerIndex].data
		for tileIndex, tile in ipairs(layer.data) do
			local tileValue = tonumber(tile)
			if tileValue == nil then
				error(
					"room "
						.. tostring(roomIndex)
						.. " layer "
						.. tostring(layerIndex)
						.. " tile "
						.. tostring(tileIndex)
						.. " must be numeric"
				)
			end
			if tileValue ~= 0 then
				resultData[tileIndex] = tile
			end
		end
	end
end

outputs[1] = result
