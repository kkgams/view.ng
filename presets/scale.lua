local value = inputs[1]
if value == nil then
    error("value is required")
end

local factor = tonumber(inputs[2])
if factor == nil then
    error("factor must be a number")
end

local function scale_numbers(current, path)
    local currentType = type(current)

    if currentType == "number" then
        return current * factor
    end

    if currentType == "table" then
        local scaled = {}
        for key, nestedValue in pairs(current) do
            scaled[key] = scale_numbers(nestedValue, path .. "." .. tostring(key))
        end
        return scaled
    end

    error(path .. " must be a number or table, got " .. currentType)
end

outputs[1] = scale_numbers(value, "value")
