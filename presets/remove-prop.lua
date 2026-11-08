-- Remove Prop
-- Removes values at arbitrary paths from one decoded value.
-- Inputs: value, path
--   path examples: props.tilesets, layers[1], layers[1].props.name
--   path may be a string or an array of path strings.
--   Bracket indexes are one-based: layers[1] is the first layer.
-- Outputs: value

local function fail(message)
	error(message)
end

local data = inputs[1]
if data == nil or data == "" then
	fail("value is required")
end
if type(data) ~= "table" then
	fail("value must be an object/array")
end

local pathValue = inputs[2]
if pathValue == nil or pathValue == "" then
	fail("path is required")
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

local function normalizePathList(value, name)
	local paths = {}
	if type(value) == "string" then
		paths[1] = value
	elseif type(value) == "table" then
		for index, path in ipairs(value) do
			if type(path) ~= "string" or path == "" then
				fail(name .. "[" .. tostring(index) .. "] must be a non-empty string")
			end
			paths[#paths + 1] = path
		end
	else
		fail(name .. " must be a string or array of path strings")
	end

	if #paths == 0 then
		fail(name .. " must contain at least one path")
	end
	return paths
end

local function parsePath(path)
	local parts = {}
	local position = 1

	while position <= #path do
		local char = string.sub(path, position, position)
		if char == "." then
			position = position + 1
		elseif char == "[" then
			local closePosition = string.find(path, "]", position, true)
			if closePosition == nil then
				fail("path has an unclosed bracket: " .. path)
			end
			local indexText = string.sub(path, position + 1, closePosition - 1)
			local index = tonumber(indexText)
			if index == nil or math.floor(index) ~= index or index < 1 then
				fail("path bracket index must be a one-based integer: " .. path)
			end
			parts[#parts + 1] = index
			position = closePosition + 1
		else
			local nextDot = string.find(path, ".", position, true) or (#path + 1)
			local nextBracket = string.find(path, "[", position, true) or (#path + 1)
			local endPosition = math.min(nextDot, nextBracket) - 1
			local key = string.sub(path, position, endPosition)
			if key == "" then
				fail("path segment must not be empty: " .. path)
			end
			parts[#parts + 1] = key
			position = endPosition + 1
		end
	end

	if #parts == 0 then
		fail("path must not be empty")
	end
	return parts
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

local function removePath(root, path)
	local parts = parsePath(path)
	local current = root
	for index = 1, #parts - 1 do
		if type(current) ~= "table" then
			fail("path parent is not an object/array: " .. path)
		end
		current = current[parts[index]]
		if current == nil then
			fail("path not found: " .. path)
		end
	end

	if type(current) ~= "table" then
		fail("path parent is not an object/array: " .. path)
	end

	local key = parts[#parts]
	if current[key] == nil then
		fail("path not found: " .. path)
	end
	if type(key) == "number" and is_array(current) then
		table.remove(current, key)
	else
		current[key] = nil
	end
end

local result = deep_copy(data)
for _, path in ipairs(normalizePathList(pathValue, "path")) do
	removePath(result, path)
end

outputs[1] = result
