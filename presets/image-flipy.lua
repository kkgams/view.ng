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

local function flipImage(image, label)
	if image == nil or image == "" or image == 0 then
		error(label .. " is required")
	end

	return host.call("image/image::transform", image, { "vertical" })
end

local image = inputs[1]
if type(image) == "table" and isArray(image) then
	local transformed = {}
	for index, item in ipairs(image) do
		transformed[index] = flipImage(item, "image[" .. tostring(index) .. "]")
	end
	outputs[1] = transformed
else
	outputs[1] = flipImage(image, "image input")
end
