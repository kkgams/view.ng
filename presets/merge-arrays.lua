local inputIds = {}
for key, isActive in pairs(inputs.active) do
	if type(key) == "number" and isActive then
		inputIds[#inputIds + 1] = key
	end
end
table.sort(inputIds)

local function assertArray(value, label)
	if value == nil then
		error(label .. " is nil")
	end
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
			error(label .. " item '" .. index .. "' is nil")
		end
	end

	return count
end

local result = {}

if #inputIds == 1 then
	local inputId = inputIds[1]
	local outer = inputs[inputId]
	local outerCount = assertArray(outer, "input '" .. inputId .. "'")
	for outerIndex = 1, outerCount do
		local inner = outer[outerIndex]
		local innerCount = assertArray(inner, "input '" .. inputId .. "' item '" .. outerIndex .. "'")
		for innerIndex = 1, innerCount do
			result[#result + 1] = inner[innerIndex]
		end
	end
else
	for _, inputId in ipairs(inputIds) do
		local value = inputs[inputId]
		local count = assertArray(value, "input '" .. inputId .. "'")
		for index = 1, count do
			result[#result + 1] = value[index]
		end
	end
end

outputs[1] = result
