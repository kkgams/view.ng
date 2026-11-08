local rects = inputs[1]
if rects == nil then
	error("rects input is required")
end

local width = inputs[2]
if width == nil or width == "" then
	width = "1"
end

local height = inputs[3]
if height == nil or height == "" then
	height = "1"
end

local padding = inputs[4]
if padding == nil or padding == "" then
	padding = "0"
end

local autoSize = inputs[5]
if autoSize == nil or autoSize == "" then
	autoSize = "true"
end

local autoSizeBool = autoSize == true or autoSize == "true" or autoSize == "1" or autoSize == 1
local requestRects = {}

local function isRect(value)
	return type(value) == "table" and (value.width ~= nil or value.height ~= nil or value.id ~= nil)
end

local function collectRects(node, path)
	if type(node) ~= "table" then
		error("Rect tree item at " .. path .. " must be an array or rect object")
	end

	if isRect(node) then
		local flatIndex = #requestRects + 1
		local rectId = tonumber(node.id) or flatIndex
		local rectWidth = tonumber(node.width) or 0
		local rectHeight = tonumber(node.height) or 0
		if rectWidth <= 0 or rectHeight <= 0 then
			error("Rect width and height at " .. path .. " must be positive")
		end

		requestRects[flatIndex] = {
			id = rectId,
			width = rectWidth,
			height = rectHeight,
		}
		node.id = rectId
		return
	end

	for index, child in ipairs(node) do
		collectRects(child, path .. "[" .. tostring(index) .. "]")
	end
end

collectRects(rects, "rects")

local request = {
	width = tonumber(width) or 1,
	height = tonumber(height) or 1,
	padding = tonumber(padding) or 0,
	["auto-size"] = autoSizeBool,
	rects = requestRects,
}

local response = host.call("pack/pack::pack", request)
if type(response) ~= "table" then
	error("pack-rects: pack response must be a table")
end
if type(response.rects) ~= "table" then
	error("pack-rects: pack response rects must be an array")
end

local atlasWidth = tonumber(response.width) or 0
local atlasHeight = tonumber(response.height) or 0
if atlasWidth <= 0 or atlasHeight <= 0 then
	error("pack-rects: response atlas width and height must be positive")
end

local packedIndex = 0

local function applyPackedRects(node, path)
	if type(node) ~= "table" then
		error("Rect tree item at " .. path .. " must be an array or rect object")
	end

	if isRect(node) then
		packedIndex = packedIndex + 1
		local packedRect = response.rects[packedIndex]
		if type(packedRect) ~= "table" then
			error("pack-rects: missing packed rect " .. tostring(packedIndex) .. " for " .. path)
		end
		if packedRect.packed ~= true then
			error("pack-rects: rect " .. tostring(packedIndex) .. " at " .. path .. " was not packed")
		end

		local x = tonumber(packedRect.x)
		local y = tonumber(packedRect.y)
		local rectWidth = tonumber(packedRect.width) or tonumber(node.width) or 0
		local rectHeight = tonumber(packedRect.height) or tonumber(node.height) or 0
		if x == nil or y == nil then
			error("pack-rects: packed rect " .. tostring(packedIndex) .. " at " .. path .. " is missing x/y")
		end
		if rectWidth <= 0 or rectHeight <= 0 then
			error("pack-rects: packed rect " .. tostring(packedIndex) .. " at " .. path .. " width and height must be positive")
		end

		node.x = x
		node.y = y
		node.width = rectWidth
		node.height = rectHeight
		node.packed = true

		local uv = {
			x / atlasWidth,
			y / atlasHeight,
			(x + rectWidth) / atlasWidth,
			(y + rectHeight) / atlasHeight,
		}
		node.uv = uv

		return uv
	end

	local uvs = {}
	for index, child in ipairs(node) do
		uvs[index] = applyPackedRects(child, path .. "[" .. tostring(index) .. "]")
	end
	return uvs
end

local uvs = applyPackedRects(rects, "rects")

outputs[1] = rects
outputs[2] = uvs
outputs[3] = atlasWidth
outputs[4] = atlasHeight
