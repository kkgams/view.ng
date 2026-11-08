local schemaJson = inputs[1]
if schemaJson == nil or schemaJson == "" then
    outputs[1] = ""
    outputs[2] = "schema is required"
    return
end

local outputFile = inputs[2]
if outputFile == nil or outputFile == "" then
    outputs[1] = ""
    outputs[2] = "outputFile is required"
    return
end

local slotsJson = inputs[3]
if slotsJson == nil or slotsJson == "" then slotsJson = "[]" end

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
    if ok then return true, text end
    if string.sub(path, 1, 5) == "demo/" then
        return safeCall("fs/fs::read-text", string.sub(path, 6))
    end
    return false, text
end

local function isPureMarker(value, key)
    if type(value) ~= "table" or type(value[key]) ~= "string" then
        return false
    end
    local count = 0
    for _ in pairs(value) do count = count + 1 end
    return count == 1
end

local function resolveSchema(schemaText)
    local ok, decoded = pcall(json.decode, schemaText)
    if not ok or not isPureMarker(decoded, "_file") then
        return true, schemaText
    end
    local path = decoded["_file"]
    if path == "" then
        return false, "schema _file must be a non-empty string"
    end
    return readText(path)
end

local okSlots, slots = pcall(json.decode, slotsJson)
if not okSlots or type(slots) ~= "table" then
    outputs[1] = ""
    outputs[2] = "slots must be a JSON array"
    return
end

local okSchema, resolvedSchema = resolveSchema(schemaJson)
if not okSchema then
    outputs[1] = ""
    outputs[2] = tostring(resolvedSchema or "failed to read schema")
    return
end

local resolvedSlotsJson = json.encode(slots)
local okBuild, rspkBytes = callRespack("build", resolvedSchema, resolvedSlotsJson)
if not okBuild then
    outputs[1] = ""
    outputs[2] = tostring(rspkBytes ~= "" and rspkBytes or "respack.build failed")
    return
end

local okDirs, dirErr = ensureParentDirs(outputFile)
if not okDirs then
    outputs[1] = ""
    outputs[2] = dirErr
    return
end

local okWriteFile, writeFileText = safeCall("fs/fs::write-file", outputFile, rspkBytes)
if not okWriteFile then
    outputs[1] = ""
    outputs[2] = tostring(writeFileText ~= "" and writeFileText or "failed to write respack output")
    return
end

outputs[1] = outputFile
outputs[2] = ""
