-- Assign Minimap Shapes - Pipeline Step
-- Reads a tree JSON file, assigns random readable minimap masks to each node,
-- and writes the updated tree JSON.
-- Inputs: tree, out
-- Outputs: out (success), error (failure)

local ROOM_SHAPES = {
	"#",
	"##",
	"#/#",
	"##/#.",
	"##/.#",
	"##/##",
	"##/##/##",
	"###/###",
	"##/#./#.",
	"##/.#/.#",
	"#../###",
	"..#/###",
	"###/.#.",
	".#./###",
}

local function randomIndex(count)
	return math.random(count)
end

local tree = inputs[1]
if tree == nil then
	error("tree must be defined")
	return
end

if #tree == 0 then
	error("tree must contain at least one node")
	return
end

for index, node in ipairs(tree) do
	if type(node) ~= "table" then
		error("tree node " .. tostring(index) .. " must be an object")
		return
	end
	if node.data == nil then
		node.data = {}
	elseif type(node.data) ~= "table" then
		error("tree node " .. tostring(index) .. " data must be an object")
		return
	end

	local shapeIndex = randomIndex(#ROOM_SHAPES)
	if shapeIndex == nil then
		return
	end
	node.data.minimap = ROOM_SHAPES[shapeIndex]
end

outputs[1] = tree
