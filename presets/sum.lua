-- Sum
-- Adds two numeric inputs.

local left = tonumber(inputs[1])
if left == nil then
	error("left must be a number")
end

local right = tonumber(inputs[2])
if right == nil then
	error("right must be a number")
end

outputs[1] = left + right
