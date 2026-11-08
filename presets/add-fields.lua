-- Add Fields
-- Adds one amount to selected direct fields on an object or every object in an array.
-- Returns a deep copy and does not mutate the input value.

local function dense_array_length(value)
	if type(value) ~= "table" then
		return nil
	end

	local length = 0
	for key, _ in pairs(value) do
		if type(key) ~= "number" or key ~= math.floor(key) or key < 1 then
			return nil
		end
		if key > length then
			length = key
		end
	end

	for index = 1, length do
		if value[index] == nil then
			return nil
		end
	end

	return length
end

local function deep_copy(value)
	if type(value) ~= "table" then
		return value
	end

	local copied = {}
	for key, item in pairs(value) do
		copied[deep_copy(key)] = deep_copy(item)
	end
	return copied
end

if not inputs.active[1] then
	error("value is not connected")
end
local value = inputs[1]
if type(value) ~= "table" then
	error("value must be an object or array of objects")
end

if not inputs.active[2] then
	error("fields is not connected")
end
local fields = inputs[2]
local field_count = dense_array_length(fields)
if field_count == nil then
	error("fields must be an array")
end
if field_count == 0 then
	error("fields must contain at least one field name")
end

local seen_fields = {}
for index, field in ipairs(fields) do
	if type(field) ~= "string" or field == "" then
		error("fields item '" .. tostring(index) .. "' must be a non-empty string")
	end
	if seen_fields[field] then
		error("fields contains duplicate field '" .. field .. "'")
	end
	seen_fields[field] = true
end

if not inputs.active[3] then
	error("amount is not connected")
end
local amount = inputs[3]
if type(amount) ~= "number" then
	error("amount must be a number")
end

local function add_to_object(object, label)
	if type(object) ~= "table" then
		error(label .. " must be an object")
	end

	local result = deep_copy(object)
	for _, field in ipairs(fields) do
		local field_value = object[field]
		if field_value == nil then
			error(label .. " field '" .. field .. "' is nil")
		end
		if type(field_value) ~= "number" then
			error(label .. " field '" .. field .. "' must be a number")
		end
		result[field] = field_value + amount
	end
	return result
end

local item_count = dense_array_length(value)
if item_count == nil then
	outputs[1] = add_to_object(value, "value")
	return
end

local result = {}
for index = 1, item_count do
	result[index] = add_to_object(value[index], "value item '" .. tostring(index) .. "'")
end
outputs[1] = result
