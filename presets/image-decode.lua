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

local function decodeImage(base64, label)
	if base64 == nil or base64 == "" then
		error(label .. " is required")
	end
	if type(base64) ~= "string" then
		error(label .. " must be a string")
	end

	return host.call("image/image::decode-base64", base64)
end

local base64 = inputs[1]
if type(base64) == "table" then
	if not isArray(base64) then
		error("base64 input must be a string or array of strings")
	end

	local images = {}
	for index, item in ipairs(base64) do
		images[index] = decodeImage(item, "base64[" .. tostring(index) .. "]")
	end
	outputs[1] = images
else
	outputs[1] = decodeImage(base64, "base64 input")
end
