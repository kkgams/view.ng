-- Apply Automap Rules - Pipeline Step 5
-- Reads rule/input tilemaps, calls the pure automap component, and writes output.
-- Inputs: rulesMap, inputMap, outputMap
-- Outputs: outputMap (success), error (failure)

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
	if tm == nil then
		return nil
	end
	if tm == json.null then
		return json.null
	end
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
local rulesMap = inputs[1]
if rulesMap == nil then
	error("rules must be provided")
end
local inputMap = inputs[2]
if inputMap == nil then
	error("input map must be provided")
end
local outputMap = inputs[3]
if outputMap == nil then
	outputMap = json.null
end

result =
	host.call("automap/automap::apply", tilemap_to_wit(rulesMap), tilemap_to_wit(inputMap), tilemap_to_wit(outputMap))
outputs[1] = tilemap_from_wit(result)
