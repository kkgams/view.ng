-- Image Atlas
-- Builds one atlas from matching trees of rects and image resources.

local function fail(message)
	error("image-atlas: " .. message)
end

local function isRect(value)
	return type(value) == "table" and (value.width ~= nil or value.height ~= nil or value.x ~= nil or value.y ~= nil)
end

local function arrayLength(value, label)
	if type(value) ~= "table" then
		return nil
	end

	local length = 0
	local hasNumericKey = false
	local hasOtherKey = false
	for key, _ in pairs(value) do
		if type(key) == "number" then
			hasNumericKey = true
			if key < 1 or key ~= math.floor(key) then
				fail(label .. " must be a dense array")
			end
			length = math.max(length, key)
		else
			hasOtherKey = true
		end
	end

	if hasOtherKey then
		if hasNumericKey then
			fail(label .. " must not mix array and object keys")
		end
		return nil
	end

	for index = 1, length do
		if value[index] == nil then
			fail(label .. " must be a dense array")
		end
	end
	return length
end

local function number(value, label)
	if type(value) ~= "number" then
		fail(label .. " must be a number")
	end
	return value
end

local function validateRect(rect, label)
	local x = number(rect.x, label .. ".x")
	local y = number(rect.y, label .. ".y")
	local width = number(rect.width, label .. ".width")
	local height = number(rect.height, label .. ".height")
	if width <= 0 or height <= 0 then
		fail(label .. " width and height must be positive")
	end
	return x, y, width, height
end

local leaves = {}
local function collect(rectNode, imageNode, label)
	if isRect(rectNode) then
		if arrayLength(imageNode, label .. " image") ~= nil then
			fail(label .. " rect and image structures must match")
		end
		if imageNode == nil or imageNode == "" or imageNode == 0 then
			fail(label .. " image is required")
		end

		local x, y, width, height = validateRect(rectNode, label .. " rect")
		leaves[#leaves + 1] = {
			rect = { x = x, y = y, width = width, height = height },
			image = imageNode,
		}
		return
	end

	local rectCount = arrayLength(rectNode, label .. " rects")
	if rectCount == nil then
		fail(label .. " rect must be a rect object or nested array")
	end
	local imageCount = arrayLength(imageNode, label .. " images")
	if imageCount == nil or imageCount ~= rectCount then
		fail(label .. " rect and image structures must match")
	end

	for index = 1, rectCount do
		collect(rectNode[index], imageNode[index], label .. "[" .. tostring(index) .. "]")
	end
end

collect(inputs[1], inputs[2], "input")
if #leaves == 0 then
	fail("no images to build atlas from")
end

local atlasWidth = tonumber(inputs[3]) or 0
local atlasHeight = tonumber(inputs[4]) or 0
for _, leaf in ipairs(leaves) do
	atlasWidth = math.max(atlasWidth, leaf.rect.x + leaf.rect.width)
	atlasHeight = math.max(atlasHeight, leaf.rect.y + leaf.rect.height)
end

local operations = {}
for index, leaf in ipairs(leaves) do
	operations[index] = {
		src = leaf.image,
		at = {
			x = math.floor(leaf.rect.x),
			y = math.floor(leaf.rect.y),
		},
	}
end

local atlas = host.call("image/image::create", atlasWidth, atlasHeight, json.null)
local blitted = host.call("image/image::blit-many", atlas, operations)
if blitted == nil then
	fail("image.blit-many failed")
end

outputs[1] = blitted
