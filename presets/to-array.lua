local inputIds = {}
for key, _ in pairs(inputs.active) do
	if type(key) == "number" then
		inputIds[#inputIds + 1] = key
	end
end
table.sort(inputIds)

local result = {}
for _, inputId in ipairs(inputIds) do
	if not inputs.active[inputId] then
		error("value '" .. inputId .. "' is not connected")
	end
	local value = inputs[inputId]
	if value == nil then
		error("value '" .. inputId .. "' is nil")
	end
	result[#result + 1] = value
end

outputs[1] = result
