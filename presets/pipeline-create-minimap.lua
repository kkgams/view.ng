-- Create Minimap - Pipeline Step 4
-- Calls minimap.comp to generate tilemap visualization from tree
-- Inputs: tree, map, direction (legacy/ignored)
-- Outputs: map (success), error (failure)
---@type { call: fun(target: string, ...): any }
_G.host = host
---@type any[]
_G.inputs = inputs
---@type any[]
_G.outputs = outputs

local function mapToEntries(map)
	local entries = {}
	local keys = {}
	for key, _ in pairs(map or {}) do
		keys[#keys + 1] = tostring(key)
	end
	table.sort(keys)
	for _, key in ipairs(keys) do
		entries[#entries + 1] = { key, tostring(map[key] or "") }
	end

	return entries
end

local function entriesToMap(entries)
	local map = {}

	for _, entry in ipairs(entries or {}) do
		map[tostring(entry[1])] = tostring(entry[2] or "")
	end

	if next(map) == nil then
		return nil
	end

	return map
end

local function treeToWit(tree)
	local witTree = {}
	for index, node in ipairs(tree) do
		witTree[index] = {
			["parent-id"] = node.parent,
			data = mapToEntries(node.data),
		}
	end
	return witTree
end

local function tileMapFromWit(witTileMap)
	local tileMap = {
		layers = {},
		props = entriesToMap(witTileMap.props),
	}
	for index, layer in ipairs(witTileMap.layers or {}) do
		tileMap.layers[index] = {
			width = layer.width,
			data = layer.data or {},
			props = entriesToMap(layer.props),
		}
	end
	return tileMap
end

local tree = inputs[1]

local okGen, witTileMap = pcall(host.call, "minimap/minimap::gen", treeToWit(tree))
if not okGen then
	error("minimap generation failed: " .. tostring(witTileMap))
end

outputs[1] = tileMapFromWit(witTileMap)
