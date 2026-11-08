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

local function callImage(method, payload)
	local resultText = host.call("image/image::" .. string.gsub(method, "_", "-"), payload)
	local ok, response = pcall(json.decode, resultText)
	if not ok then
		return nil, "Failed to parse image." .. method .. " response: " .. (resultText:sub(1, 100))
	end
	if not response.ok then
		return nil, response.message or response.code or ("image." .. method .. " failed")
	end
	return response, nil
end

local function parseInput(value)
	if value == nil or value == "" then
		return {}
	end
	if type(value) == "string" then
		local ok, decoded = pcall(json.decode, value)
		if ok then
			return decoded
		end
	end
	return value
end

local function imageHandle(image, label)
	local handle = nil
	if type(image) == "table" then
		handle = tonumber(image.handle)
	elseif type(image) == "number" or type(image) == "string" then
		handle = tonumber(image)
	end

	if handle == nil or handle == 0 then
		error(label .. " is missing handle")
	end
	return handle
end

local images = parseInput(inputs[1])
if type(images) == "table" and isArray(images) then
	local closed = 0
	for index, image in ipairs(images) do
		local response, closeError = callImage("close", { src = imageHandle(image, "image[" .. tostring(index) .. "]") })
		if response == nil then
			outputs[1] = tostring(closed)
			outputs[2] = closeError or ("Failed to close image " .. tostring(index))
			return
		end
		closed = closed + (tonumber(response.closed) or 1)
	end
	outputs[1] = tostring(closed)
	outputs[2] = ""
else
	local response, closeError = callImage("close", { src = imageHandle(images, "image input") })
	if response == nil then
		outputs[1] = "0"
		outputs[2] = closeError or "Failed to close image"
		return
	end
	outputs[1] = tostring(tonumber(response.closed) or 1)
	outputs[2] = ""
end
