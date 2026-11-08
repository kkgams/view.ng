-- Unique Values
-- Recursively removes duplicate values from every nested dense array.
-- Array order and the first occurrence of each value are preserved.
-- Nested arrays are compared structurally after their own duplicates are removed.

local function fail(message)
	error("unique-values: " .. message)
end

local function array_length(value, label)
	if type(value) ~= "table" then
		fail(label .. " must be an array")
	end

	local length = 0
	for key, _ in pairs(value) do
		if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
			fail(label .. " must contain only positive integer keys")
		end
		if key > length then
			length = key
		end
	end

	for index = 1, length do
		if value[index] == nil then
			fail(label .. " must be a dense array; item " .. tostring(index) .. " is missing")
		end
	end

	return length
end

local function values_equal(left, right)
	if type(left) ~= type(right) then
		return false
	end
	if type(left) ~= "table" then
		return left == right
	end
	if #left ~= #right then
		return false
	end
	for index = 1, #left do
		if not values_equal(left[index], right[index]) then
			return false
		end
	end
	return true
end

local function unique_array(value, label)
	local length = array_length(value, label)
	local result = {}

	for index = 1, length do
		local item = value[index]
		local normalized = item
		if type(item) == "table" then
			normalized = unique_array(item, label .. "[" .. tostring(index) .. "]")
		end

		local duplicate = false
		for _, existing in ipairs(result) do
			if values_equal(normalized, existing) then
				duplicate = true
				break
			end
		end
		if not duplicate then
			result[#result + 1] = normalized
		end
	end

	return result
end

if not inputs.active[1] then
	fail("values is not connected")
end

outputs[1] = unique_array(inputs[1], "values")
