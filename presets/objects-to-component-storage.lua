-- Objects to Component Storage
-- Projects World Object properties into ECS component storage while preserving each
-- object's zero-based source index as its entity id.
--
-- Inputs:
--   objects: dense array of objects
--   fields:
--     - non-empty array of direct field names: objects containing every required field
--       become array components whose values follow the requested field order
--     - non-empty direct field name: objects containing that field become components
--       whose values are the field values themselves
--   defaults: optional object keyed by field name. In array mode, a missing field uses
--     its default; fields without defaults remain required.
--
-- Output:
--   storage: { entity_ids = { ... }, components = { ... } }

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

local function dense_array_length(value, label)
	if type(value) ~= "table" then
		error(label .. " must be an array")
	end

	local length = 0
	for key, _ in pairs(value) do
		if type(key) ~= "number" or key ~= math.floor(key) or key < 1 then
			error(label .. " must contain only positive integer keys")
		end
		if key > length then
			length = key
		end
	end

	for index = 1, length do
		if value[index] == nil then
			error(label .. " item '" .. tostring(index) .. "' is nil")
		end
	end

	return length
end

if not inputs.active[1] then
	error("objects is not connected")
end
local objects = inputs[1]
local object_count = dense_array_length(objects, "objects")

if not inputs.active[2] then
	error("fields is not connected")
end
local fields = inputs[2]
local property = nil
local seen_fields = {}
if type(fields) == "string" then
	if fields == "" then
		error("fields must be a non-empty field name or array of field names")
	end
	property = fields
elseif type(fields) == "table" then
	local field_count = dense_array_length(fields, "fields")
	if field_count == 0 then
		error("fields must contain at least one field name")
	end

	for field_index, field in ipairs(fields) do
		if type(field) ~= "string" or field == "" then
			error("fields item '" .. tostring(field_index) .. "' must be a non-empty string")
		end
		if seen_fields[field] then
			error("fields contains duplicate field '" .. field .. "'")
		end
		seen_fields[field] = true
	end
else
	error("fields must be a non-empty field name or array of field names")
end

local defaults = {}
if inputs.active[3] then
	defaults = inputs[3]
	if type(defaults) ~= "table" then
		error("defaults must be an object")
	end

	if property ~= nil and next(defaults) ~= nil then
		error("defaults can only be used when fields is an array")
	end

	for field, _ in pairs(defaults) do
		if type(field) ~= "string" or field == "" then
			error("defaults must contain only non-empty field-name keys")
		end
		if not seen_fields[field] then
			error("defaults contains field '" .. field .. "' not listed in fields")
		end
	end
end

local storage = {
	entity_ids = {},
	components = {},
}

for object_index = 1, object_count do
	local object = objects[object_index]
	if type(object) ~= "table" then
		error("objects item '" .. tostring(object_index) .. "' must be an object")
	end

	if property ~= nil then
		local component = object[property]
		if component ~= nil then
			storage.entity_ids[#storage.entity_ids + 1] = object_index - 1
			storage.components[#storage.components + 1] = component
		end
	else
		local component = {}
		local matches = true
		for field_index, field in ipairs(fields) do
			local field_value = object[field]
			if field_value == nil then
				local default_value = defaults[field]
				if default_value == nil then
					matches = false
					break
				end
				field_value = deep_copy(default_value)
			end
			component[field_index] = field_value
		end

		if matches then
			storage.entity_ids[#storage.entity_ids + 1] = object_index - 1
			storage.components[#storage.components + 1] = component
		end
	end
end

outputs[1] = storage
