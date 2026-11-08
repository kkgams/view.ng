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

	return true, length
end

local function imageResource(image, label)
	if image == nil or image == "" then
		error(label .. " is required")
	end
	if type(image) ~= "table" then
		error(label .. " resource must be a table")
	end

	local resource = image.resource or image.image
	if resource == nil and image["$resource"] ~= nil then
		resource = image
	end
	if type(resource) ~= "table" then
		error(label .. " resource is required")
	end

	return resource
end

local function itemAt(value, index, label)
	if type(value) == "table" and isArray(value) then
		local item = value[index]
		if item == nil then
			error(label .. " must contain item " .. tostring(index))
		end
		return item
	end
	return value
end

local function saveImage(image, path, format, label)
	local resource = imageResource(image, label)

	if path == nil or path == "" then
		error(label .. " path is required")
	end
	if type(path) ~= "string" then
		error(label .. " path must be a string")
	end

	if format == nil or format == "" then
		format = "qoi"
	end
	if type(format) ~= "string" then
		error(label .. " format must be a string")
	end

	host.call("image/image::save", resource, path, format)
	return path
end

local image = inputs[1]
local path = inputs[2]
local format = inputs[3]

local imagesAreArray, imageCount = isArray(image)
if type(image) == "table" and imagesAreArray then
	local paths = {}
	for index, item in ipairs(image) do
		paths[index] = saveImage(
			item,
			itemAt(path, index, "path"),
			itemAt(format, index, "format"),
			"image[" .. tostring(index) .. "]"
		)
	end
	if #paths ~= imageCount then
		error("image input must be a dense array of images")
	end
	outputs[1] = paths
else
	outputs[1] = saveImage(image, path, format, "image input")
end
