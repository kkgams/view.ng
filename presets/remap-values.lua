-- Remap Values
-- Recursively replaces primitive values throughout an array or object.
-- Object keys are preserved. Values absent from originalIDs are unchanged.

local function fail(message)
	error("remap-values: " .. message)
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

local function primitive(value, label)
	if type(value) == "table" or type(value) == "function" or type(value) == "thread" or type(value) == "userdata" then
		fail(label .. " must be a primitive value")
	end
	return value
end

local function equal(left, right)
	return type(left) == type(right) and left == right
end

if not inputs.active[1] then
	fail("value is not connected")
end
if not inputs.active[2] then
	fail("originalIDs is not connected")
end
if not inputs.active[3] then
	fail("newIDs is not connected")
end

local value = inputs[1]
local originalIDs = inputs[2]
local newIDs = inputs[3]
local originalCount = array_length(originalIDs, "originalIDs")
local newCount = array_length(newIDs, "newIDs")

if originalCount == 0 then
	fail("originalIDs must contain at least one value")
end
if originalCount ~= newCount then
	fail("originalIDs and newIDs must have equal lengths")
end

for index = 1, originalCount do
	primitive(originalIDs[index], "originalIDs[" .. tostring(index) .. "]")
	primitive(newIDs[index], "newIDs[" .. tostring(index) .. "]")
	for previous = 1, index - 1 do
		if equal(originalIDs[index], originalIDs[previous]) then
			fail("originalIDs contains duplicate value at indexes " .. tostring(previous) .. " and " .. tostring(index))
		end
	end
end

local function remap(node)
	if type(node) == "table" then
		local result = {}
		for key, item in pairs(node) do
			result[key] = remap(item)
		end
		return result
	end

	for index = 1, originalCount do
		if equal(node, originalIDs[index]) then
			return newIDs[index]
		end
	end
	return node
end

outputs[1] = remap(value)
