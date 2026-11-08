local paths = inputs[1]

local function isArray(value)
	if type(value) ~= "table" then
		return false
	end
	local length = 0
	for key, _ in pairs(value) do
		if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
			return false
		end
		if key > length then
			length = key
		end
	end
	for index = 1, length do
		if value[index] == nil then
			return false
		end
	end
	return true
end

if type(paths) == "string" then
	paths = { paths }
elseif not isArray(paths) then
	outputs[1] = ""
	outputs[2] = "paths must be string or array"
	return
end

local patterns = {}
for index, path in ipairs(paths) do
	if type(path) ~= "string" or path == "" then
		outputs[1] = ""
		outputs[2] = "path " .. tostring(index) .. " must be non-empty string"
		return
	end
	patterns[#patterns + 1] = host.call("fs/fs::read-text", path)
end

-- One respack slot: BulletPatterns = vector BulletPattern.
-- Keep BulletML files as raw JSON to preserve empty object `{}` shape across encoding.
outputs[1] = "[[" .. table.concat(patterns, ",") .. "]]"
outputs[2] = ""
