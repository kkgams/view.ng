local schemaJson = inputs[1]
if schemaJson == nil or schemaJson == "" then
	outputs[1] = ""
	outputs[2] = ""
	outputs[3] = "schema is required"
	return
end

local outputFile = inputs[2]
if outputFile == nil then
	outputFile = ""
end

local function safeCall(target, ...)
	local ok, result = pcall(host.call, target, ...)
	if not ok then
		return false, tostring(result or "")
	end
	return true, result
end

local function callRespack(method, ...)
	return safeCall("respack/respack::" .. string.gsub(method, "_", "-"), ...)
end

local function ensureParentDirs(path)
	local dir = string.match(path, "^(.*)/[^/]*$")
	if dir == nil or dir == "" then
		return true, ""
	end
	local current = ""
	for part in string.gmatch(dir, "[^/]+") do
		if current == "" then
			current = part
		else
			current = current .. "/" .. part
		end
		local ok, err = safeCall("fs/fs::create-dir", current)
		if not ok then
			local statOk = safeCall("fs/fs::stat", current)
			if not statOk then
				return false, tostring(err ~= "" and err or "failed to create directory: " .. current)
			end
		end
	end
	return true, ""
end

local function readText(path)
	local ok, text = safeCall("fs/fs::read-text", path)
	if ok then
		return true, text
	end
	if string.sub(path, 1, 5) == "demo/" then
		return safeCall("fs/fs::read-text", string.sub(path, 6))
	end
	return false, text
end

local function isPureFileMarker(value)
	if type(value) ~= "table" or type(value["_file"]) ~= "string" then
		return false
	end
	local count = 0
	for _ in pairs(value) do
		count = count + 1
	end
	return count == 1
end

local function resolveSchema(schemaText)
	local ok, decoded = pcall(json.decode, schemaText)
	if not ok or not isPureFileMarker(decoded) then
		return true, schemaText
	end
	local path = decoded["_file"]
	if path == "" then
		return false, "schema _file must be a non-empty string"
	end
	return readText(path)
end

local okSchema, resolvedSchema = resolveSchema(schemaJson)
if not okSchema then
	outputs[1] = ""
	outputs[2] = ""
	outputs[3] = tostring(resolvedSchema or "failed to read schema")
	return
end

local okGenerate, odinSource = callRespack("generate_odin", resolvedSchema)
if not okGenerate then
	outputs[1] = ""
	outputs[2] = ""
	outputs[3] = tostring(odinSource ~= "" and odinSource or "respack.generate_odin failed")
	return
end

if outputFile ~= "" then
	local okDirs, dirErr = ensureParentDirs(outputFile)
	if not okDirs then
		outputs[1] = odinSource
		outputs[2] = ""
		outputs[3] = dirErr
		return
	end

	local okWrite, writeText = safeCall("fs/fs::write-text", outputFile, odinSource)

	if not okWrite then
		outputs[1] = odinSource
		outputs[2] = ""
		outputs[3] = tostring(writeText ~= "" and writeText or "failed to write Odin source")
		return
	end
end

outputs[1] = odinSource
outputs[2] = outputFile
outputs[3] = ""
