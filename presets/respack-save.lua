local schema = inputs[1]
local slots = inputs[2]
local path_bin = inputs[3]
local path_decoder = inputs[4]

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

local function readText(path)
	local ok, text = pcall(host.call, "fs/fs::read-text", path)
	if ok then
		return text
	end
	if string.sub(path, 1, 5) == "demo/" then
		return host.call("fs/fs::read-text", string.sub(path, 6))
	end
	error(text)
end

local function isPureFileMarker(value)
	if type(value) ~= "table" or type(value["_file"]) ~= "string" then
		return false
	end
	local count = 0
	for _ in pairs(value) do
		count = count + 1
	end
	return count == 1
end

local function resolveSchema(value)
	if type(value) ~= "string" or value == "" then
		error("schema is required")
	end

	local ok, decoded = pcall(json.decode, value)
	if ok then
		if isPureFileMarker(decoded) then
			local path = decoded["_file"]
			if path == "" then
				error("schema _file must be a non-empty string")
			end
			return readText(path)
		end
		return value
	end

	return readText(value)
end

schema = resolveSchema(schema)
local odin_code = host.call("respack/respack::generate-odin", schema)
ensureParentDirs(path_decoder)
host.call("fs/fs::write-text", path_decoder, odin_code)

local slots_json = nil
if type(slots) == "string" then
	slots_json = slots
else
	slots_json = json.encode(slots)
end
ensureParentDirs(path_bin)
host.call("respack/respack::build-to-file", schema, slots_json, path_bin)
