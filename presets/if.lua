local condition = inputs[1]
local value = inputs[2]

if value == nil then
    value = condition
end

local function truthy(value)
    if value == nil or value == false then
        return false
    end
    if type(value) == "number" then
        return value ~= 0
    end
    if type(value) ~= "string" then
        return true
    end

    local text = value:match("^%s*(.-)%s*$")
    local lowered = string.lower(text)
    if lowered == "" or lowered == "false" or lowered == "no" or lowered == "off" or lowered == "null" or lowered == "nil" or lowered == "0" then
        return false
    end
    return true
end

local active = truthy(condition)

outputs[1] = value
outputs[2] = value
outputs.active[1] = active
outputs.active[2] = not active
