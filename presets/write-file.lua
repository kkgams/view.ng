local function isArray(value)
	if type(value) ~= "table" then
		return false, 0
	end

	local length = 0
	for key, _ in pairs(value) do
		if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
			return false, 0
		end
		if key > length then
			length = key
		end
	end

	for index = 1, length do
		if value[index] == nil then
			return false, 0
		end
	end

	return true, length
end

local function ensureParentDirs(path)
	local dir = string.match(path, "^(.*)/[^/]*$")
	if dir == nil or dir == "" then
		return
	end
	local current = ""
	for part in string.gmatch(dir, "[^/]+") do
		if current == "" then
			current = part
		else
			current = current .. "/" .. part
		end
		pcall(host.call, "fs/fs::create-dir", current)
	end
end

local function writeFile(path, content)
	if path == nil or path == "" then
		error("path is required")
	end
	if type(path) ~= "string" then
		error("path must be string")
	end

	if type(content) ~= "string" then
		content = json.encode(content)
	end

	ensureParentDirs(path)
	host.call("fs/fs::write-text", path, content)
	return path
end

local path = inputs[1]
local content = inputs[2]

if type(path) == "table" then
	local okPaths, pathCount = isArray(path)
	local okContents, contentCount = isArray(content)
	if not okPaths then
		error("path must be string or array")
	end
	if not okContents then
		error("text must be array when path is array")
	end
	if pathCount ~= contentCount then
		error("path and text arrays must have the same length")
	end

	local written = {}
	for index, itemPath in ipairs(path) do
		written[index] = writeFile(itemPath, content[index])
	end
	outputs[1] = written
else
	outputs[1] = writeFile(path, content)
end
