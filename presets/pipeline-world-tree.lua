-- World Tree Generator - Pipeline Step 1
-- Calls treegen plugin to generate procedural tree
-- Inputs: nodeCount, maxDepth, maxBranching, rootBranches, src
-- Outputs: src (success), error (failure)

---@type string[]
_G.inputs = inputs
---@type { call: fun(target: string, ...): any }
_G.host = host
---@type { encode: fun(value: any): string }
_G.json = json

local nodeCount = inputs[1]
if nodeCount == nil or nodeCount == "" then
	nodeCount = "10"
end
local maxDepth = inputs[2]
if maxDepth == nil or maxDepth == "" then
	maxDepth = "0"
end
local maxBranching = inputs[3]
if maxBranching == nil or maxBranching == "" then
	maxBranching = "0"
end
local rootBranches = inputs[4]
if rootBranches == nil or rootBranches == "" then
	rootBranches = "0"
end

local generatedTree = host.call("tree-generator/tree-generator::gen", {
	["node-count"] = tonumber(nodeCount) or 10,
	["max-depth"] = tonumber(maxDepth) or 0,
	["max-branching"] = tonumber(maxBranching) or 0,
	["root-branches"] = tonumber(rootBranches) or 0,
})

local tree = {}
for index, node in ipairs(generatedTree) do
	local data = {}
	for _, entry in ipairs(node.data or {}) do
		data[tostring(entry[1])] = tostring(entry[2] or "")
	end
	tree[index] = {
		parent = node["parent-id"],
		data = data,
	}
end

outputs[1] = tree -- Return the tree
outputs[2] = "" -- No error
