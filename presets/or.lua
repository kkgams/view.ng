if inputs.active[1] then
    outputs[1] = inputs[1]
elseif inputs.active[2] then
    outputs[1] = inputs[2]
else
    outputs[1] = nil
    outputs.active[1] = false
end
