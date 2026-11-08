-- Image Open
-- Opens image paths while preserving any nested array structure.

local function fail(message)
	error("image-open: " .. message)
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
		fail(label .. " must be a string or nested array of strings")
	end

	for index = 1, length do
		if value[index] == nil then
			fail(label .. " must be a dense array")
		end
	end
	return length
end

local function open(value, label)
	if type(value) == "string" then
		if value == "" then
			fail(label .. " is required")
		end
		local ok, image = pcall(host.call, "image/image::open", value)
		if not ok then
			fail(label .. " " .. string.format("%q", value) .. ": " .. tostring(image))
		end
		return image
	end

	local length = arrayLength(value, label)
	if length == nil then
		if value == nil then
			fail(label .. " is required")
		end
		fail(label .. " must be a string")
	end

	local images = {}
	for index = 1, length do
		images[index] = open(value[index], label .. "[" .. tostring(index) .. "]")
	end
	return images
end

outputs[1] = open(inputs[1], "path")
