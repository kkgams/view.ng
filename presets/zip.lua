-- Zip
-- Merges already-decoded Lua objects by index.
--
-- Inputs may be either:
--   * an object-like table: { id = 1, duration = 0.1 }
--   * an array-like table of object-like tables: { { id = 1 }, { id = 2 } }
--
-- Object-like inputs are broadcast to every output item. Array-like inputs are merged by
-- one-based index. Later connected inputs overwrite earlier fields with the same key.
-- This preset does not JSON-decode inputs and does not JSON-encode outputs. Use
-- json_decode/json_encode at graph boundaries when needed. Failures are thrown with error().

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

local function require_object(value, label)
	if type(value) ~= "table" then
		error(label .. " must be an object")
	end
	if next(value) ~= nil and is_array_table(value) then
		error(label .. " must be an object, not an array")
	end
end

local function collect_input_ids()
	local ids = {}

	if type(inputs.active) == "table" then
		for key, is_active in pairs(inputs.active) do
			if type(key) == "number" and is_active then
				ids[#ids + 1] = key
			end
		end
	else
		for key, value in pairs(inputs) do
			if type(key) == "number" and value ~= nil and value ~= "" then
				ids[#ids + 1] = key
			end
		end
	end

	table.sort(ids)
	return ids
end

local inputs_to_zip = {}
local output_count = 0

for _, input_id in ipairs(collect_input_ids()) do
	local value = inputs[input_id]
	if value ~= nil and value ~= "" then
		if type(value) ~= "table" then
			error("Input " .. tostring(input_id) .. " must be an object or array of objects")
		end

		if is_array_table(value) then
			for index, item in ipairs(value) do
				require_object(item, "Input " .. tostring(input_id) .. " item " .. tostring(index))
			end
			inputs_to_zip[#inputs_to_zip + 1] = {
				kind = "array",
				items = value,
			}
			if #value > output_count then
				output_count = #value
			end
		else
			require_object(value, "Input " .. tostring(input_id))
			inputs_to_zip[#inputs_to_zip + 1] = {
				kind = "single",
				item = value,
			}
			if output_count < 1 then
				output_count = 1
			end
		end
	end
end

local result = {}

for index = 1, output_count do
	local merged = {}

	for _, input_info in ipairs(inputs_to_zip) do
		local item = nil
		if input_info.kind == "single" then
			item = input_info.item
		else
			item = input_info.items[index]
		end

		if item ~= nil then
			for key, value in pairs(item) do
				merged[key] = value
			end
		end
	end

	result[#result + 1] = merged
end

outputs[1] = result
