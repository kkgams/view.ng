local tilemap = inputs[1]
local diff = tonumber(inputs[2])

if tilemap == nil or tilemap == "" then
	error("tilemap input is required")
end

if type(tilemap) ~= "table" then
	error("tilemap input must be a table")
end

if diff == nil then
	error("diff input must be a number")
end

local layers = tilemap.layers
if type(layers) ~= "table" then
	error("tilemap.layers must be a table")
end

for layer_index, layer in ipairs(layers) do
	if type(layer.data) ~= "table" then
		error("tilemap.layers[" .. layer_index .. "] must be a table")
	end

	for tile_index, tile in ipairs(layer.data) do
		if tile > 0 then
			layer.data[tile_index] = math.max(0, tile - diff)
		end
	end
	tilemap.layers[layer_index] = layer
end

outputs[1] = tilemap
