-- Room Item Placer
--
-- Appends free-form item entries to rooms in the generated world tree.
--
-- Intended graph position:
--   World Tree Generator
--     -> Minimap Shape Assigner
--     -> Keylock Progression Annotator
--     -> Room Item Placer
--     -> Minimap Generator
--
-- Inputs:
--   1. tree
--      Array of nodes in the existing demo shape:
--        { parent = <parent node index or -1>, data = { [string] = string } }
--      The tree is one-based in Lua arrays. The root node must be tree[1] and must
--      have parent = -1. Non-root parent values use the zero-based ids emitted by
--      the tree generator, so tree[2].parent == 0 means parent is tree[1].
--
--   2. items
--      Array of free-form JSON/Lua values. Elements may be strings, numbers,
--      booleans, arrays, or objects. This node treats each element as opaque data
--      and places each element into one room.
--
--   3. fieldName
--      Optional node.data field name to append to. Defaults to "items".
--
-- Output:
--   1. tree
--      Same tree object, with node.data[fieldName] appended as a JSON array string.
--
-- Metadata written:
--   node.data[fieldName]
--      JSON array string of free-form item entries in this room. Existing values
--      are preserved and appended to, so this node can be used for multiple passes
--      such as loot placement, enemy spawn placement, or pickup placement.
--
-- Placement rules:
--   - Every input item is placed exactly once.
--   - Placement is deterministic round-robin across all rooms, including root.
--   - Item values are opaque; only the outer items input must be an array.

local tree = inputs[1]
local items = inputs[2]
local fieldName = inputs[3]

local function is_array(value)
	if type(value) ~= "table" then
		return false
	end
	local count = 0
	for key, _ in pairs(value) do
		if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
			return false
		end
		if key > count then
			count = key
		end
	end
	for index = 1, count do
		if value[index] == nil then
			return false
		end
	end
	return true
end

local function array_length(value)
	local count = 0
	for key, _ in pairs(value) do
		if key > count then
			count = key
		end
	end
	return count
end

local function validate_tree(value)
	if not is_array(value) then
		error("tree must be an array")
	end

	local count = array_length(value)
	if count == 0 then
		error("tree must contain at least one node")
	end

	for index = 1, count do
		local node = value[index]
		if type(node) ~= "table" then
			error("tree[" .. tostring(index) .. "] must be an object")
		end

		local parent = node.parent
		if type(parent) ~= "number" or parent ~= math.floor(parent) then
			error("tree[" .. tostring(index) .. "].parent must be an integer")
		end

		if index == 1 then
			if parent ~= -1 then
				error("tree root must have parent -1")
			end
		else
			local parentIndex = parent + 1
			if parentIndex < 1 or parentIndex >= index then
				error("tree[" .. tostring(index) .. "].parent must reference an earlier node")
			end
		end

		if node.data == nil then
			node.data = {}
		elseif type(node.data) ~= "table" then
			error("tree[" .. tostring(index) .. "].data must be an object")
		end
	end

	return count
end

local function validate_items(value)
	if not is_array(value) then
		error("items must be an array")
	end
	return array_length(value)
end

local function normalize_field_name(value)
	if value == nil or value == "" then
		return "items"
	end
	if type(value) ~= "string" then
		error("fieldName must be a string")
	end
	return value
end

local function decode_items(raw, label)
	if raw == nil or raw == "" then
		return {}
	end
	if type(raw) ~= "string" then
		error(label .. " must be a JSON array string")
	end

	local decoded = json.decode(raw)
	if not is_array(decoded) then
		error(label .. " must decode to an array")
	end

	return decoded
end

local function append_item(nodeIndex, field, item)
	local node = tree[nodeIndex]
	local label = "tree[" .. tostring(nodeIndex) .. "].data[" .. field .. "]"
	local values = decode_items(node.data[field], label)
	values[#values + 1] = item
	node.data[field] = json.encode(values)
end

local nodeCount = validate_tree(tree)
local itemCount = validate_items(items)
local targetFieldName = normalize_field_name(fieldName)

for itemIndex = 1, itemCount do
	local nodeIndex = 1 + ((itemIndex - 1) % nodeCount)
	append_item(nodeIndex, targetFieldName, items[itemIndex])
end

outputs[1] = tree
