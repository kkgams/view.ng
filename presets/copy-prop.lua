-- Copy Prop
-- Copies values from one decoded Lua value/path to another decoded Lua value/path.
--
-- Inputs:
--   from:   source path string, or array of source path strings
--   to:     target path string, or array of target path strings
--   src:    source object/array
--   target: target object/array
--
-- Path examples: props.tilesets, layers[1], layers[1].props.name
-- Bracket indexes are one-based: layers[1] is the first layer.
-- If src and target are both arrays and the path starts with a field name, the copy is applied
-- per array item by index.
--
-- Output: target
-- This preset works on already-decoded Lua values. It does not JSON-decode inputs and does not
-- JSON-encode outputs. Failures are thrown with error().

local function fail(message)
	error(message)
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

local function is_array(value)
	if type(value) ~= "table" then
		return false
	end

	local count = 0
	for key, _ in pairs(value) do
		if type(key) ~= "number" or key < 1 or math.floor(key) ~= key then
			return false
		end
		count = count + 1
	end

	return count == #value
end

local function normalize_path_list(value, name)
	local paths = {}
	if type(value) == "string" then
		if value == "" then
			fail(name .. " must be a non-empty path")
		end
		paths[1] = value
	elseif type(value) == "table" then
		if not is_array(value) then
			fail(name .. " must be a path string or array of path strings")
		end
		for index, path in ipairs(value) do
			if type(path) ~= "string" or path == "" then
				fail(name .. "[" .. tostring(index) .. "] must be a non-empty path string")
			end
			paths[#paths + 1] = path
		end
	else
		fail(name .. " must be a path string or array of path strings")
	end

	if #paths == 0 then
		fail(name .. " must contain at least one path")
	end
	return paths
end

local function parse_path(path)
	local parts = {}
	local position = 1

	while position <= #path do
		local char = string.sub(path, position, position)
		if char == "." then
			position = position + 1
		elseif char == "[" then
			local close_position = string.find(path, "]", position, true)
			if close_position == nil then
				fail("path has an unclosed bracket: " .. path)
			end
			local index_text = string.sub(path, position + 1, close_position - 1)
			local index = tonumber(index_text)
			if index == nil or math.floor(index) ~= index or index < 1 then
				fail("path bracket index must be a one-based integer: " .. path)
			end
			parts[#parts + 1] = index
			position = close_position + 1
		else
			local next_dot = string.find(path, ".", position, true) or (#path + 1)
			local next_bracket = string.find(path, "[", position, true) or (#path + 1)
			local end_position = math.min(next_dot, next_bracket) - 1
			local key = string.sub(path, position, end_position)
			if key == "" then
				fail("path segment must not be empty: " .. path)
			end
			parts[#parts + 1] = key
			position = end_position + 1
		end
	end

	if #parts == 0 then
		fail("path must not be empty")
	end
	return parts
end

local function get_path(root, parts, path)
	local current = root
	for _, part in ipairs(parts) do
		if type(current) ~= "table" then
			fail("source path parent is not an object/array: " .. path)
		end
		current = current[part]
		if current == nil then
			fail("source path not found: " .. path)
		end
	end
	return current
end

local function set_path(root, parts, path, value)
	local current = root
	for index = 1, #parts - 1 do
		if type(current) ~= "table" then
			fail("target path parent is not an object/array: " .. path)
		end
		local key = parts[index]
		if current[key] == nil then
			current[key] = {}
		elseif type(current[key]) ~= "table" then
			fail("target path parent already exists and is not an object/array: " .. path)
		end
		current = current[key]
	end

	if type(current) ~= "table" then
		fail("target path parent is not an object/array: " .. path)
	end
	current[parts[#parts]] = deep_copy(value)
end

local function should_copy_per_item(src_root, target_root, src_parts, target_parts)
	return is_array(src_root) and is_array(target_root) and type(src_parts[1]) ~= "number" and type(target_parts[1]) ~= "number"
end

local from_paths = normalize_path_list(inputs[1], "from")
local to_paths = normalize_path_list(inputs[2], "to")
if #from_paths ~= #to_paths then
	fail("from and to must contain the same number of paths")
end

local src = inputs[3]
if src == nil or src == "" then
	fail("src is required")
end
if type(src) ~= "table" then
	fail("src must be an object/array")
end

local target = inputs[4]
if target == nil or target == "" then
	fail("target is required")
end
if type(target) ~= "table" then
	fail("target must be an object/array")
end

local result = deep_copy(target)

for index, from_path in ipairs(from_paths) do
	local to_path = to_paths[index]
	local from_parts = parse_path(from_path)
	local to_parts = parse_path(to_path)

	if should_copy_per_item(src, result, from_parts, to_parts) then
		if #src ~= #result then
			fail("src and target arrays must have the same length for per-item copy")
		end
		for item_index = 1, #src do
			set_path(
				result[item_index],
				to_parts,
				to_path,
				get_path(src[item_index], from_parts, from_path)
			)
		end
	else
		set_path(result, to_parts, to_path, get_path(src, from_parts, from_path))
	end
end

outputs[1] = result
