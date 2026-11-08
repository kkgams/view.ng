-- LUT Generator
-- Converts arrays of integers into RGBA LUT images.
-- Nested arrays are preserved; widths must have the same nested structure,
-- with one positive integer width for each leaf array of values.

local function fail(message)
	error("lut-generator: " .. message)
end

local function arrayLength(value, label)
	if type(value) ~= "table" then
		fail(label .. " must be an array")
	end

	local length = 0
	for key, _ in pairs(value) do
		if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
			fail(label .. " must be a dense array")
		end
		length = math.max(length, key)
	end

	if length == 0 then
		fail(label .. " must not be empty")
	end

	for index = 1, length do
		if value[index] == nil then
			fail(label .. " must be a dense array")
		end
	end

	return length
end

local function generateLut(values, width, label)
	if type(width) ~= "number" or width < 1 or width ~= math.floor(width) then
		fail(label .. " width must be a positive integer")
	end
	if #values % width ~= 0 then
		fail(label .. " value count must be divisible by width")
	end

	local bytes = {}
	for index, value in ipairs(values) do
		if type(value) ~= "number" or value ~= math.floor(value) then
			fail(label .. "[" .. tostring(index) .. "] must be an integer")
		end

		local tileId = math.max(0, value)
		local offset = (index - 1) * 4
		bytes[offset + 1] = tileId % 256
		bytes[offset + 2] = math.floor(tileId / 256) % 256
		bytes[offset + 3] = math.floor(tileId / 65536) % 256
		bytes[offset + 4] = 255
	end

	local image, writeErr = host.call("image/image::from-pixels", width, #values / width, "rgba8", bytes)
	if image == nil then
		fail(writeErr or (label .. " failed to create image from pixel data"))
	end
	return image
end

local function convert(values, widths, label)
	local length = arrayLength(values, label)
	local itemType = type(values[1])

	if itemType == "number" then
		for index = 2, length do
			if type(values[index]) ~= "number" then
				fail(label .. " must contain only integers or only nested arrays")
			end
		end
		return generateLut(values, widths, label)
	end

	if itemType == "table" then
		for index = 2, length do
			if type(values[index]) ~= "table" then
				fail(label .. " must contain only integers or only nested arrays")
			end
		end

		if type(widths) ~= "table" then
			fail(label .. " widths must be an array")
		end
		local widthLength = arrayLength(widths, label .. " widths")
		if widthLength ~= length then
			fail(label .. " values and widths must have matching lengths")
		end

		local result = {}
		for index = 1, length do
			result[index] = convert(
				values[index],
				widths[index],
				label .. "[" .. tostring(index) .. "]"
			)
		end
		return result
	end

	fail(label .. "[1] must be an integer or a nested array")
end

outputs[1] = convert(inputs[1], inputs[2], "input")
