-- toObject
-- Builds an object from all active named inputs.
--
-- Each connected input becomes one object field, using the input port name as the key.
-- Rename input ports to control the produced object shape.
--
-- Output:
--   object: { [inputName] = inputValue, ... }

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

local object = {}
for _, inputId in ipairs(inputIds) do
	local key = inputs.names[inputId]
	if type(key) ~= "string" or key == "" then
		error("input '" .. tostring(inputId) .. "' must have a non-empty name")
	end
	local value = inputs[inputId]
	if value == nil then
		error("input '" .. key .. "' is nil")
	end
	object[key] = value
end

outputs[1] = object
