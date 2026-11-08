-- Keylock Progression Annotator
--
-- Enriches the generated world tree with lock/key progression metadata before the
-- minimap/tilemap steps.
--
-- Intended graph position:
--   World Tree Generator
--     -> Minimap Shape Assigner
--     -> Keylock Progression Annotator
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
--   2. locks
--      Array of non-empty lock ids, for example:
--        { "lock.red", "lock.blue" }
--
--   3. keys
--      Array of non-empty key ids, for example:
--        { "key.red", "key.blue" }
--
-- Pairing contract:
--   locks[i] requires keys[i]. locks and keys must have exactly the same length.
--
-- Output:
--   1. tree
--      Same tree object, with node.data annotated using flat string metadata so it
--      remains compatible with the current tree/minimap WIT shape.
--
-- Metadata written:
--   node.data.keys
--      JSON array string of key ids granted by entering/clearing this room.
--
--   node.data.locks
--      JSON array string of lock ids on this room's entrance from its parent.
--      Because every room has a single parent, a lock on a child node means the
--      door/edge from parent -> child is locked.
--
--   node.data.lockRequires
--      JSON object string mapping lock id -> key id for locks on this room.
--
-- Placement rules:
--   - Root cannot have locks.
--   - Every key and every lock from the inputs is placed, or the node errors.
--   - A room may contain multiple locks.
--   - A key is placed on a node reachable before its paired lock is added.
--   - A lock is placed on a child room with a greater array index than its key room.
--     The tree generator emits parents before children, so this keeps the key outside
--     the newly locked subtree.
--
-- This is intentionally a Lua pipeline step, not a restored legacy Keylock plugin.

local tree = inputs[1]
local locks = inputs[2]
local keys = inputs[3]

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

local function validate_id_array(name, value)
	if not is_array(value) then
		error(name .. " must be an array")
	end

	local seen = {}
	local count = array_length(value)
	for index = 1, count do
		local id = value[index]
		if type(id) ~= "string" or id == "" then
			error(name .. "[" .. tostring(index) .. "] must be a non-empty string")
		end
		if seen[id] then
			error(name .. " contains duplicate id " .. id)
		end
		seen[id] = true
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

local function decode_string_array(raw, label)
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

	local result = {}
	local count = array_length(decoded)
	for index = 1, count do
		local item = decoded[index]
		if type(item) ~= "string" or item == "" then
			error(label .. "[" .. tostring(index) .. "] must be a non-empty string")
		end
		result[index] = item
	end
	return result
end

local function decode_string_map(raw, label)
	if raw == nil or raw == "" then
		return {}
	end
	if type(raw) ~= "string" then
		error(label .. " must be a JSON object string")
	end

	local decoded = json.decode(raw)
	if type(decoded) ~= "table" or is_array(decoded) then
		error(label .. " must decode to an object")
	end

	local result = {}
	for key, value in pairs(decoded) do
		if type(key) ~= "string" or key == "" then
			error(label .. " contains an invalid key")
		end
		if type(value) ~= "string" or value == "" then
			error(label .. "[" .. key .. "] must be a non-empty string")
		end
		result[key] = value
	end
	return result
end

local function append_unique(array, value, label)
	for _, item in ipairs(array) do
		if item == value then
			error(label .. " already contains " .. value)
		end
	end
	array[#array + 1] = value
end

local function node_keys(node, nodeIndex)
	return decode_string_array(node.data.keys, "tree[" .. tostring(nodeIndex) .. "].data.keys")
end

local function node_locks(node, nodeIndex)
	return decode_string_array(node.data.locks, "tree[" .. tostring(nodeIndex) .. "].data.locks")
end

local function node_lock_requires(node, nodeIndex)
	return decode_string_map(node.data.lockRequires, "tree[" .. tostring(nodeIndex) .. "].data.lockRequires")
end

local function write_node_keys(node, values)
	node.data.keys = json.encode(values)
end

local function write_node_locks(node, values)
	node.data.locks = json.encode(values)
end

local function write_node_lock_requires(node, values)
	node.data.lockRequires = json.encode(values)
end

local function collect_reachable(count)
	local ownedKeys = {}
	local reachable = {}

	local changed = true
	while changed do
		changed = false
		for index = 1, count do
			local node = tree[index]
			local canReach = false

			if index == 1 then
				canReach = true
			else
				local parentIndex = node.parent + 1
				canReach = reachable[parentIndex] == true
				if canReach then
					local locksHere = node_locks(node, index)
					local requiresHere = node_lock_requires(node, index)
					for _, lockId in ipairs(locksHere) do
						local requiredKey = requiresHere[lockId]
						if requiredKey == nil then
							error("tree[" .. tostring(index) .. "].data.lockRequires is missing key requirement for " .. lockId)
						end
						if not ownedKeys[requiredKey] then
							canReach = false
							break
						end
					end
				end
			end

			if canReach and not reachable[index] then
				reachable[index] = true
				changed = true
			end

			if reachable[index] then
				for _, keyId in ipairs(node_keys(node, index)) do
					if not ownedKeys[keyId] then
						ownedKeys[keyId] = true
						changed = true
					end
				end
			end
		end
	end

	return reachable, ownedKeys
end

local function choose_key_node(lockIndex, count)
	local reachable = collect_reachable(count)
	local limit = lockIndex - 1
	if limit < 1 then
		error("cannot place key before lock target " .. tostring(lockIndex))
	end

	for index = limit, 1, -1 do
		if reachable[index] then
			return index
		end
	end

	error("no reachable key room exists before lock target " .. tostring(lockIndex))
end

local function add_key(nodeIndex, keyId)
	local node = tree[nodeIndex]
	local values = node_keys(node, nodeIndex)
	append_unique(values, keyId, "tree[" .. tostring(nodeIndex) .. "].data.keys")
	write_node_keys(node, values)
end

local function add_lock(nodeIndex, lockId, keyId)
	local node = tree[nodeIndex]
	local locksHere = node_locks(node, nodeIndex)
	local requiresHere = node_lock_requires(node, nodeIndex)

	append_unique(locksHere, lockId, "tree[" .. tostring(nodeIndex) .. "].data.locks")
	if requiresHere[lockId] ~= nil then
		error("tree[" .. tostring(nodeIndex) .. "].data.lockRequires already contains " .. lockId)
	end
	requiresHere[lockId] = keyId

	write_node_locks(node, locksHere)
	write_node_lock_requires(node, requiresHere)
end

local nodeCount = validate_tree(tree)
local lockCount = validate_id_array("locks", locks)
local keyCount = validate_id_array("keys", keys)

if lockCount ~= keyCount then
	error("locks and keys must have the same length")
end

if lockCount > 0 and nodeCount < 2 then
	error("cannot place locks in a tree with only the root node")
end

for pairIndex = 1, lockCount do
	local lockId = locks[pairIndex]
	local keyId = keys[pairIndex]
	local lockNodeIndex = 2 + ((pairIndex - 1) % (nodeCount - 1))
	local keyNodeIndex = choose_key_node(lockNodeIndex, nodeCount)

	add_key(keyNodeIndex, keyId)
	add_lock(lockNodeIndex, lockId, keyId)

	local reachableAfter = collect_reachable(nodeCount)
	if not reachableAfter[lockNodeIndex] then
		error("internal error: placed lock " .. lockId .. " but target room is not reachable after placing key " .. keyId)
	end
end

outputs[1] = tree
