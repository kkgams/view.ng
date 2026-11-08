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

local function readJson(path)
	if path == nil or path == "" then
		return nil, "path is required"
	end
	if type(path) ~= "string" then
		return nil, "path must be string"
	end

	local content = host.call("fs/fs::read-text", path)
	return json.decode(content), ""
end

local path = inputs[1]
if type(path) == "table" then
	local okArray = isArray(path)
	if not okArray then
		outputs[1] = nil
		outputs[2] = "path must be string or array"
	else
		local data = {}
		local err = ""
		for index, itemPath in ipairs(path) do
			local item, itemErr = readJson(itemPath)
			if itemErr ~= "" then
				err = "item " .. tostring(index) .. ": " .. itemErr
				data = nil
				break
			end
			data[index] = item
		end
		outputs[1] = data
		outputs[2] = err
	end
else
	local data, err = readJson(path)
	outputs[1] = data
	outputs[2] = err
end
