-- Tilemap Scaler
-- Reads a tilemap, calls the pure scaler component, and writes the scaled tilemap.
-- Inputs: inputMap, outputMap, scaleFactor
-- Outputs: outputMap (success), error (failure)

local inputMap = inputs[1]
if inputMap == nil or inputMap == "" then
	error("input map is requred")
end

local outputMap = inputs[2]
if outputMap == nil or outputMap == "" then
	outputMap = nil
end

local scaleFactor = inputs[3]
if scaleFactor == nil or scaleFactor == "" then
	error("scale factor is requred")
end

local function map_to_entries(props)
	local entries = {}
	if props == nil then
		return entries
	end
	for key, value in pairs(props) do
		entries[#entries + 1] = { key, value }
	end
	return entries
end

local function entries_to_map(entries)
	if entries == nil or #entries == 0 then
		return nil
	end
	local props = {}
	for _, entry in ipairs(entries) do
		props[entry[1]] = entry[2]
	end
	return props
end

local function tilemap_to_wit(tm)
	local layers = {}
	for i, layer in ipairs(tm.layers or {}) do
		layers[i] = {
			width = layer.width,
			data = layer.data or {},
			props = map_to_entries(layer.props),
		}
	end
	return {
		layers = layers,
		props = map_to_entries(tm.props),
	}
end

local function tilemap_from_wit(tm)
	local layers = {}
	for i, layer in ipairs(tm.layers or {}) do
		layers[i] = {
			width = layer.width,
			data = layer.data or {},
			props = entries_to_map(layer.props),
		}
	end
	return {
		layers = layers,
		props = entries_to_map(tm.props),
	}
end

local function optional_size(value)
	if value == nil or value == "" then
		return 1
	end
	local size = tonumber(value)
	if size == nil then
		error("door size must be a number")
	end
	return size
end

local parsedScaleFactor = tonumber(scaleFactor)
if parsedScaleFactor == nil then
	error("scale factor must be a number")
end

local opt = {}
opt["scale-factor"] = parsedScaleFactor
opt["door-sizes"] = {
	north = { width = optional_size(inputs[4]), height = optional_size(inputs[5]) },
	east = { width = optional_size(inputs[6]), height = optional_size(inputs[7]) },
	south = { width = optional_size(inputs[8]), height = optional_size(inputs[9]) },
	west = { width = optional_size(inputs[10]), height = optional_size(inputs[11]) },
}
local scaleResult = host.call("scaler/scaler::scale", tilemap_to_wit(inputMap), opt)

outputs[1] = tilemap_from_wit(scaleResult)
