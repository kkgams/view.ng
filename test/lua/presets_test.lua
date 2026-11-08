-- Run from repository root with the preset file paths as arguments.
assert(#arg > 0, "preset files are required")
for _, path in ipairs(arg) do
    -- Import must only return the node function: no inputs, APIs or globals exist.
    local module = assert(loadfile(path, "t", {}))()
    assert(type(module) == "function", path .. " must return a node function")
end

local function node(name)
    return assert(loadfile("presets/" .. name .. ".lua", "t", _G))()
end

local function execute(run, values, outputCount)
    local inputs = { active = {}, names = {} }
    for id, value in pairs(values) do
        inputs[id] = value
        inputs.active[id] = true
    end
    local outputs = { active = {}, names = {} }
    for id = 1, outputCount or 1 do outputs.active[id] = true end
    run(inputs, outputs, { runId = "preset-test" })
    return outputs
end

local sum = node("sum")
assert(execute(sum, { 3, 4 })[1] == 7)
assert(execute(sum, { 10, -2 })[1] == 8, "cached functions must use current arguments")
assert(not pcall(execute, sum, { "invalid", 1 }))

local original = { 2, nested = { 3 } }
local scaled = execute(node("scale"), { original, 4 })[1]
assert(scaled[1] == 8 and scaled.nested[1] == 12)
assert(original[1] == 2 and original.nested[1] == 3)
assert(execute(node("array-length"), { { 1, false, 3 } })[1] == 3)
assert(not pcall(execute, node("array-length"), { { [1] = 1, [3] = 3 } }))
local at = node("array-at")
assert(execute(at, { { "first", "last" }, -1 })[1] == "last")
assert(execute(at, { { "only" }, 2 }).active[1] == false)
local branch = execute(node("if"), { false, "value" }, 2)
assert(branch[1] == "value" and branch[2] == "value")
assert(branch.active[1] == false and branch.active[2] == true)
assert(execute(node("or"), { false, "fallback" })[1] == false)
local array = execute(node("to-array"), { [2] = "second", [1] = "first" })[1]
assert(#array == 2 and array[1] == "first" and array[2] == "second")
local split = execute(node("from-array"), { { "only" } }, 2)
assert(split[1] == "only" and split.active[2] == false)

-- Exercise a converted preset through the actual graph compiler/executor.
local json = dofile("test/lua/json.lua")
local env = setmetatable({ json = json, import = function(path)
    return assert(loadfile(path, "t", _G))()
end }, { __index = _G })
assert(loadfile("src/lua/compile-graph.lua", "t", env))()
local graph = [=[
[
 {"id":1,"kind":4,"name":"left","inputs":[],"outputs":[{"id":1,"name":"value","value":"3"}]},
 {"id":2,"kind":4,"name":"right","inputs":[],"outputs":[{"id":1,"name":"value","value":"4"}]},
 {"id":3,"kind":2,"name":"sum","codePath":"presets/sum.lua","inputs":[{"id":1,"name":"left","srcNodeId":1,"srcOutputId":1},{"id":2,"name":"right","srcNodeId":2,"srcOutputId":1}],"outputs":[{"id":1,"name":"value","value":null}]},
 {"id":4,"kind":1,"name":"goal","inputs":[{"id":1,"name":"answer","srcNodeId":3,"srcOutputId":1}],"outputs":[]}
]
]=]
local compiled = env.main({ graphJson = graph, sourcePath = "root.ng.lua" })
assert(compiled.diagnostic == json.null, compiled.diagnostic)
local executable = assert(load(compiled.source, "@root.ng.lua", "t", env))()
assert(executable.main().goal.inputs.answer == 7)
print("Preset module tests passed: " .. #arg .. " side-effect-free imports, numeric/array/branch behavior and compiled graph execution")
