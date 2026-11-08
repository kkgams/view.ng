-- Pick
-- Selects a subset of fields from one decoded Lua object/table or from each object in a decoded Lua array.
--
-- Expected input format:
--   inputs[1] "items": a Lua table that is either:
--     * an object-like table: { id = 1, name = "hero", hp = 10 }
--     * an array-like table of object-like tables: { { id = 1, name = "hero" }, { id = 2, name = "slime" } }
--   inputs[2] "fields": a non-empty array-like table of names: { "id", "name" }
--
-- This preset works on already-decoded Lua values. It does not JSON-decode inputs and does not
-- JSON-encode outputs. Use json_decode/json_encode nodes at the graph boundary when needed.
-- Outputs: items. Failures are thrown with error().

local function fail(message)
	error(message)
end

local function is_array_table(value)
	if type(value) ~= "table" then
		return false
	end

	local length = 0
	for key, _ in pairs(value) do
		if type(key) ~= "number" or key ~= math.floor(key) or key < 1 then
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

local function normalize_fields(value)
	local fields = {}

	if value == nil or value == "" then
		fail("fields is required")
	end

	if type(value) ~= "table" then
		fail("fields must be an array of field names")
	end

	if not is_array_table(value) then
		fail("fields must be an array of field names")
	end

	for index, field in ipairs(value) do
		if type(field) ~= "string" or field == "" then
			fail("fields[" .. tostring(index) .. "] must be a non-empty string")
		end
		fields[#fields + 1] = field
	end

	if #fields == 0 then
		fail("fields must contain at least one field name")
	end

	return fields
end

local function pick_fields(item, fields, label)
	if type(item) ~= "table" then
		fail(label .. " must be an object")
	end

	local copy = {}
	for _, field in ipairs(fields) do
		if item[field] ~= nil then
			copy[field] = item[field]
		end
	end
	return copy
end

local items = inputs[1]
if items == nil or items == "" then
	fail("items is required")
end
if type(items) ~= "table" then
	fail("items must be an object or array of objects")
end

local fields = normalize_fields(inputs[2])

if is_array_table(items) then
	local picked = {}
	for index, item in ipairs(items) do
		picked[#picked + 1] = pick_fields(item, fields, "Item " .. tostring(index))
	end
	outputs[1] = picked
	return
end

outputs[1] = pick_fields(items, fields, "Item")
