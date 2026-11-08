-- toObjectEach
-- Builds an array of objects from active named array inputs.
--
-- Each connected input becomes one object field, using the input port name as the key.
-- Input arrays are zipped by one-based index:
--   id = { 1, 2 }, name = { "a", "b" }
-- becomes:
--   { { id = 1, name = "a" }, { id = 2, name = "b" } }
--
-- Output:
--   objects: { { [inputName] = inputValueAtIndex, ... }, ... }

local function array_length(value, label)
	if type(value) ~= "table" then
		error(label .. " must be an array")
	end

	local count = 0
	for key, _ in pairs(value) do
		if type(key) ~= "number" or key ~= math.floor(key) or key < 1 then
			error(label .. " must contain only positive integer keys")
		end
		if key > count then
			count = key
		end
	end

	for index = 1, count do
		if value[index] == nil then
			error(label .. " item '" .. tostring(index) .. "' is nil")
		end
	end

	return count
end

local inputIds = {}
for key, isActive in pairs(inputs.active) do
	if type(key) == "number" and isActive then
		inputIds[#inputIds + 1] = key
	end
end
table.sort(inputIds)

if #inputIds == 0 then
	error("at least one named input is required")
end

local fields = {}
local expectedCount = nil

for _, inputId in ipairs(inputIds) do
	local fieldName = inputs.names[inputId]
	if type(fieldName) ~= "string" or fieldName == "" then
		error("input '" .. tostring(inputId) .. "' must have a non-empty name")
	end

	local value = inputs[inputId]
	if value == nil then
		error("input '" .. fieldName .. "' is nil")
	end

	local count = array_length(value, "input '" .. fieldName .. "'")
	if expectedCount == nil then
		expectedCount = count
	elseif count ~= expectedCount then
		error("input '" .. fieldName .. "' length " .. tostring(count) .. " does not match expected length " .. tostring(expectedCount))
	end

	fields[#fields + 1] = {
		name = fieldName,
		values = value,
	}
end

local objects = {}
for index = 1, expectedCount do
	local object = {}
	for _, field in ipairs(fields) do
		object[field.name] = field.values[index]
	end
	objects[index] = object
end

outputs[1] = objects
