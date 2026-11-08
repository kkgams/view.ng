local value = inputs[1]
if value == nil then value = "" end

local resultText = host.call("image/image::close-all")
local ok, response = pcall(json.decode, resultText)
if not ok then
    outputs[1] = value
    outputs[2] = ""
    outputs[3] = "Failed to parse plugin response: " .. (resultText:sub(1, 100))
    return
end

if not response.ok then
    outputs[1] = value
    outputs[2] = ""
    outputs[3] = response.message or response.code or "image.close_all failed"
    return
end

outputs[1] = value
outputs[2] = tostring(response.closed or 0)
outputs[3] = ""
