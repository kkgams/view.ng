-- Image Info
-- Returns image metadata while preserving any nested array structure.

local function fail(message)
	error("image-info: " .. message)
end

local function arrayLength(value, label)
	if type(value) ~= "table" then
		return nil
	end

	local length = 0
	local hasNumericKey = false
	local hasOtherKey = false
	for key, _ in pairs(value) do
		if type(key) == "number" then
			hasNumericKey = true
			if key < 1 or key ~= math.floor(key) then
				fail(label .. " must be a dense array")
			end
			length = math.max(length, key)
		else
			hasOtherKey = true
		end
	end

	if hasOtherKey then
		if hasNumericKey then
			fail(label .. " must not mix array and object keys")
		end
		return nil
	end

	for index = 1, length do
		if value[index] == nil then
			fail(label .. " must be a dense array")
		end
	end
	return length
end

local function imageInfo(image, label)
	if image == nil or image == "" or image == 0 then
		fail(label .. " is required")
	end
	return host.call("image/image::info", image)
end

local function collectInfo(value, label)
	local length = arrayLength(value, label)
	if length == nil then
		return imageInfo(value, label)
	end

	local infos = {}
	for index = 1, length do
		infos[index] = collectInfo(value[index], label .. "[" .. tostring(index) .. "]")
	end
	return infos
end

outputs[1] = collectInfo(inputs[1], "image")
