local source = inputs[1]
if type(source) ~= "string" then
	error("Director Compile source must be a string")
end

local irJson = host.call("director-compiler/director-compiler::compile", source)
local ir = json.decode(irJson)
local symbols = ir.symbols
if type(symbols) ~= "table" then
	error("Director Compile result must contain symbols")
end
ir.symbols = nil
outputs[1] = ir
outputs[2] = symbols
