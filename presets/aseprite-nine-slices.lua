local function isArray(value)
	if type(value) ~= "table" then
		return false
	end

	local length = 0
	for key, _ in pairs(value) do
		if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
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

local function field(value, kebab, snake)
	local result = value[kebab]
	if result ~= nil then
		return result
	end
	return value[snake]
end

local function validatePath(path, label)
	if type(path) ~= "string" or path == "" then
		error("aseprite-nine-slices: " .. label .. " must be a non-empty file path string")
	end
end

local function positiveInteger(value, label)
	local number = tonumber(value)
	if number == nil or number ~= math.floor(number) or number <= 0 then
		error("aseprite-nine-slices: " .. label .. " must be a positive integer")
	end
	return number
end

local function integer(value, label)
	local number = tonumber(value)
	if number == nil or number ~= math.floor(number) then
		error("aseprite-nine-slices: " .. label .. " must be an integer")
	end
	return number
end

local function optionValue(value)
	if value == json.null then
		return nil
	end
	if type(value) ~= "table" then
		return value
	end
	if value.is_some == false or value["is-some"] == false then
		return nil
	end
	if value.val ~= nil then
		return value.val
	end
	if value.value ~= nil then
		return value.value
	end
	return value
end

local function normalizeRequestedNames(value)
	if value == nil or value == "" then
		return {}, {}
	end
	if type(value) ~= "table" or not isArray(value) then
		error("aseprite-nine-slices: slice_names must be an array")
	end

	local names = {}
	local wanted = {}
	for index, name in ipairs(value) do
		if type(name) ~= "string" or name == "" then
			error("aseprite-nine-slices: slice_names[" .. tostring(index) .. "] must be a non-empty string")
		end
		names[#names + 1] = name
		wanted[name] = false
	end
	return names, wanted
end

local requestedNames, requestedFound = normalizeRequestedNames(inputs[2])
local hasRequestedNames = #requestedNames > 0

local frameIndex = 0
if inputs[3] ~= nil and inputs[3] ~= "" then
	frameIndex = integer(inputs[3], "frame")
	if frameIndex < 0 then
		error("aseprite-nine-slices: frame must be non-negative")
	end
end

local function selectSliceKey(slice, label)
	local keys = field(slice, "keys", "keys")
	if type(keys) ~= "table" or not isArray(keys) then
		error("aseprite-nine-slices: slice keys must be an array for " .. label)
	end

	local selected = nil
	local selectedFrame = -1
	for _, key in ipairs(keys) do
		if type(key) ~= "table" then
			error("aseprite-nine-slices: slice key must be a table for " .. label)
		end
		local keyFrame = integer(field(key, "frame", "frame"), label .. " key frame")
		if keyFrame <= frameIndex and keyFrame >= selectedFrame then
			selected = key
			selectedFrame = keyFrame
		end
	end

	if selected == nil then
		error("aseprite-nine-slices: missing slice key for frame " .. tostring(frameIndex) .. " in " .. label)
	end
	return selected
end

local function normalizePatch(key, label)
	local patch = optionValue(field(key, "patch", "patch"))
	if patch == nil then
		return nil
	end
	if type(patch) ~= "table" then
		error("aseprite-nine-slices: patch must be a table for " .. label)
	end
	return {
		x = integer(field(patch, "x", "x"), label .. " patch.x"),
		y = integer(field(patch, "y", "y"), label .. " patch.y"),
		width = positiveInteger(field(patch, "width", "width"), label .. " patch.width"),
		height = positiveInteger(field(patch, "height", "height"), label .. " patch.height"),
	}
end

local function processFile(path, label, rects, images, infos)
	validatePath(path, label)

	local doc = host.call("aseprite/aseprite::open", path)
	local docInfo = host.call("aseprite/aseprite::info", doc)
	local slices = host.call("aseprite/aseprite::slices", doc)
	local pixels = host.call("aseprite/aseprite::render-frame", doc, frameIndex)

	if type(docInfo) ~= "table" then
		error("aseprite-nine-slices: aseprite info must be a table for " .. label)
	end
	if type(slices) ~= "table" or not isArray(slices) then
		error("aseprite-nine-slices: aseprite slices must be an array for " .. label)
	end
	if type(pixels) ~= "table" then
		error("aseprite-nine-slices: rendered frame must be a table for " .. label)
	end
	if type(pixels.data) ~= "table" or not isArray(pixels.data) then
		error("aseprite-nine-slices: rendered frame data must be an array for " .. label)
	end

	local docWidth = positiveInteger(field(docInfo, "width", "width"), label .. " document width")
	local docHeight = positiveInteger(field(docInfo, "height", "height"), label .. " document height")
	local pixelsWidth = positiveInteger(field(pixels, "width", "width"), label .. " rendered width")
	local pixelsHeight = positiveInteger(field(pixels, "height", "height"), label .. " rendered height")
	if pixelsWidth ~= docWidth or pixelsHeight ~= docHeight then
		error("aseprite-nine-slices: rendered frame dimensions do not match document dimensions for " .. label)
	end
	if #pixels.data ~= docWidth * docHeight * 4 then
		error("aseprite-nine-slices: rendered frame data length does not match dimensions for " .. label)
	end

	local frameImage = host.call("image/image::from-pixels", docWidth, docHeight, "rgba8", pixels.data)
	local extractedCount = 0

	for sliceIndex, slice in ipairs(slices) do
		if type(slice) ~= "table" then
			error("aseprite-nine-slices: slice " .. tostring(sliceIndex) .. " must be a table for " .. label)
		end

		local name = tostring(field(slice, "name", "name") or "")
		if name == "" then
			error("aseprite-nine-slices: slice " .. tostring(sliceIndex) .. " is missing a name for " .. label)
		end

		local shouldExtract = not hasRequestedNames or requestedFound[name] ~= nil
		if shouldExtract then
			local key = selectSliceKey(slice, label .. " slice " .. name)
			local patch = normalizePatch(key, label .. " slice " .. name)
			if patch ~= nil then
				local x = integer(field(key, "x", "x"), label .. " slice " .. name .. " x")
				local y = integer(field(key, "y", "y"), label .. " slice " .. name .. " y")
				local width = positiveInteger(field(key, "width", "width"), label .. " slice " .. name .. " width")
				local height = positiveInteger(field(key, "height", "height"), label .. " slice " .. name .. " height")

				if x < 0 or y < 0 or x + width > docWidth or y + height > docHeight then
					error("aseprite-nine-slices: slice " .. name .. " bounds exceed document bounds for " .. label)
				end
				if patch.x < 0 or patch.y < 0 or patch.x + patch.width > width or patch.y + patch.height > height then
					error("aseprite-nine-slices: slice " .. name .. " patch bounds exceed slice bounds for " .. label)
				end

				local image = host.call("image/image::crop", frameImage, {
					x0 = x,
					y0 = y,
					x1 = x + width,
					y1 = y + height,
				})
				if image == nil then
					error("aseprite-nine-slices: image crop failed for " .. label .. " slice " .. name)
				end

				local rectId = #rects + 1
				rects[rectId] = {
					id = rectId,
					name = name,
					path = path,
					source_slice_name = name,
					source_x = x,
					source_y = y,
					width = width,
					height = height,
					size = { width, height },
					slices = { patch.x, patch.y, patch.x + patch.width, patch.y + patch.height },
				}
				images[rectId] = image
				extractedCount = extractedCount + 1
				if hasRequestedNames then
					requestedFound[name] = true
				end
			elseif hasRequestedNames then
				error("aseprite-nine-slices: requested slice " .. name .. " has no nine-slice patch for " .. label)
			end
		end
	end

	if extractedCount == 0 then
		error("aseprite-nine-slices: no nine-slice patches found for " .. label)
	end

	infos[#infos + 1] = {
		path = path,
		width = docWidth,
		height = docHeight,
		frame = frameIndex,
		slice_count = extractedCount,
	}
end

local path = inputs[1]
local rects = {}
local images = {}
local infos = {}

if type(path) == "table" then
	if not isArray(path) then
		error("aseprite-nine-slices: path input must be a path string or array of path strings")
	end
	if #path == 0 then
		error("aseprite-nine-slices: at least one file path is required")
	end
	for index, itemPath in ipairs(path) do
		processFile(itemPath, "file[" .. tostring(index) .. "]", rects, images, infos)
	end
else
	processFile(path, "file", rects, images, infos)
end

if hasRequestedNames then
	for _, name in ipairs(requestedNames) do
		if requestedFound[name] ~= true then
			error("aseprite-nine-slices: missing requested nine-slice " .. name)
		end
	end
end

if #rects ~= #images then
	error("aseprite-nine-slices: rect/image count mismatch")
end

outputs[1] = rects
outputs[2] = images
outputs[3] = {
	frame = frameIndex,
	paths = path,
	files = infos,
	count = #rects,
}
