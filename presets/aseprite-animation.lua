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

local function validatePath(path, label)
	if type(path) ~= "string" or path == "" then
		error("aseprite-animation: " .. label .. " must be a non-empty file path string")
	end
end

local animationNames = inputs[2]
if type(animationNames) ~= "table" or not isArray(animationNames) then
	error("aseprite-animation: animation_names must be an array")
end
if #animationNames == 0 then
	error("aseprite-animation: at least one animation name is required")
end

local requested = {}
for index, name in ipairs(animationNames) do
	if type(name) ~= "string" or name == "" then
		error("aseprite-animation: animation name " .. tostring(index) .. " must be a non-empty string")
	end
	requested[name] = true
end

local function field(value, kebab, snake)
	local result = value[kebab]
	if result ~= nil then
		return result
	end
	return value[snake]
end

local function repeatCount(tag)
	local value = tag["repeat"]
	if value == nil or value == false or value == "" then
		return 0
	end
	local count = tonumber(value)
	if count == nil then
		error("aseprite-animation: tag " .. tostring(tag.name or "") .. " repeat must be numeric")
	end
	count = math.floor(count)
	if count < 0 then
		error("aseprite-animation: tag " .. tostring(tag.name or "") .. " repeat must be non-negative")
	end
	return count
end

local function frameSequence(fromFrame, toFrame, direction)
	local result = {}
	if direction == "reverse" then
		for frame = toFrame, fromFrame, -1 do
			result[#result + 1] = frame
		end
	elseif direction == "ping-pong" then
		for frame = fromFrame, toFrame do
			result[#result + 1] = frame
		end
		for frame = toFrame - 1, fromFrame + 1, -1 do
			result[#result + 1] = frame
		end
	elseif direction == "ping-pong-reverse" then
		for frame = toFrame, fromFrame, -1 do
			result[#result + 1] = frame
		end
		for frame = fromFrame + 1, toFrame - 1 do
			result[#result + 1] = frame
		end
	else
		for frame = fromFrame, toFrame do
			result[#result + 1] = frame
		end
	end
	return result
end

local function processFile(path, label)
	validatePath(path, label)

	local doc = host.call("aseprite/aseprite::open", path)
	local docInfo = host.call("aseprite/aseprite::info", doc)
	local framesInfo = host.call("aseprite/aseprite::frames", doc)
	local tags = host.call("aseprite/aseprite::tags", doc)

	if type(docInfo) ~= "table" then
		error("aseprite-animation: aseprite info must be a table for " .. label)
	end
	if type(framesInfo) ~= "table" or not isArray(framesInfo) then
		error("aseprite-animation: aseprite frames must be an array for " .. label)
	end
	if type(tags) ~= "table" or not isArray(tags) then
		error("aseprite-animation: aseprite tags must be an array for " .. label)
	end

	local width = tonumber(docInfo.width) or 0
	local height = tonumber(docInfo.height) or 0
	if width <= 0 or height <= 0 then
		error("aseprite-animation: document width and height must be positive for " .. label)
	end

	local tagsByName = {}
	for _, tag in ipairs(tags) do
		local name = tostring(tag.name or "")
		if name ~= "" then
			tagsByName[name] = tag
		end
	end

	local rects = {}
	local images = {}
	local animations = {}

	for _, animationName in ipairs(animationNames) do
		local tag = tagsByName[animationName]
		if tag == nil then
			error("aseprite-animation: missing tag " .. animationName .. " for " .. label)
		end

		local fromFrame = tonumber(field(tag, "from-frame", "from_frame"))
		local toFrame = tonumber(field(tag, "to-frame", "to_frame"))
		if fromFrame == nil or toFrame == nil then
			error("aseprite-animation: tag " .. animationName .. " is missing from-frame/to-frame for " .. label)
		end
		fromFrame = math.floor(fromFrame)
		toFrame = math.floor(toFrame)
		if fromFrame < 0 or toFrame < fromFrame or toFrame >= #framesInfo then
			error("aseprite-animation: tag " .. animationName .. " frame range is out of bounds for " .. label)
		end

		local direction = tostring(tag.direction or "forward")
		local sequence = frameSequence(fromFrame, toFrame, direction)
		local rectStart = #rects + 1

		for _, frameIndex in ipairs(sequence) do
			local pixels = host.call("aseprite/aseprite::render-frame", doc, frameIndex)
			if type(pixels) ~= "table" then
				error("aseprite-animation: render-frame returned non-table for frame " .. tostring(frameIndex) .. " in " .. label)
			end
			local pixelsWidth = tonumber(pixels.width) or 0
			local pixelsHeight = tonumber(pixels.height) or 0
			if pixelsWidth ~= width or pixelsHeight ~= height then
				error("aseprite-animation: rendered frame dimensions do not match document dimensions for " .. label)
			end
			if type(pixels.data) ~= "table" or not isArray(pixels.data) then
				error("aseprite-animation: rendered frame data must be an array for " .. label)
			end
			if #pixels.data ~= width * height * 4 then
				error("aseprite-animation: rendered frame data length does not match dimensions for " .. label)
			end

			local image = host.call("image/image::from-pixels", width, height, "rgba8", pixels.data)
			local frameInfo = framesInfo[frameIndex + 1]
			if type(frameInfo) ~= "table" then
				error("aseprite-animation: missing frame info for frame " .. tostring(frameIndex) .. " in " .. label)
			end
			local durationMs = tonumber(field(frameInfo, "duration-ms", "duration_ms")) or 0
			if durationMs <= 0 then
				error("aseprite-animation: frame " .. tostring(frameIndex) .. " duration must be positive for " .. label)
			end

			local rectId = #rects + 1
			rects[rectId] = {
				id = rectId,
				animation = animationName,
				frame = frameIndex,
				width = width,
				height = height,
				duration = durationMs,
			}
			images[rectId] = image
		end

		local rectCount = #rects - rectStart + 1
		animations[#animations + 1] = {
			name = animationName,
			from_frame = fromFrame,
			to_frame = toFrame,
			direction = direction,
			rect_start = rectStart,
			rect_count = rectCount,
			frame_start = rectStart - 1,
			frame_count = rectCount,
			["repeat"] = repeatCount(tag),
		}
	end

	return rects, images, {
		path = path,
		width = width,
		height = height,
		animations = animations,
		frame_count = #rects,
	}
end

local function mergeFiles(paths)
	if #paths == 0 then
		error("aseprite-animation: at least one file path is required")
	end

	local rects = {}
	local images = {}
	local animations = {}
	local width = nil
	local height = nil

	for index, itemPath in ipairs(paths) do
		local itemRects, itemImages, itemInfo = processFile(itemPath, "file[" .. tostring(index) .. "]")

		if width == nil then
			width = itemInfo.width
			height = itemInfo.height
		elseif itemInfo.width ~= width or itemInfo.height ~= height then
			error("aseprite-animation: all files must have matching dimensions when merged")
		end

		local rectOffset = #rects
		for _, rect in ipairs(itemRects) do
			local rectId = rectOffset + rect.id
			rect.id = rectId
			rects[rectId] = rect
			images[rectId] = itemImages[rect.id - rectOffset]
		end

		for _, animation in ipairs(itemInfo.animations) do
			animation.rect_start = animation.rect_start + rectOffset
			animation.frame_start = animation.frame_start + rectOffset
			animations[#animations + 1] = animation
		end
	end

	return rects, images, {
		paths = paths,
		width = width,
		height = height,
		animations = animations,
		frame_count = #rects,
	}
end

local path = inputs[1]
if type(path) == "table" then
	if not isArray(path) then
		error("aseprite-animation: file input must be a path string or array of path strings")
	end

	local rects, images, info = mergeFiles(path)
	outputs[1] = rects
	outputs[2] = images
	outputs[3] = info
else
	local rects, images, info = processFile(path, "file")
	outputs[1] = rects
	outputs[2] = images
	outputs[3] = info
end
