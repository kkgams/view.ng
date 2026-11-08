-- Filter
-- Returns every item in a dense array that matches a filter.
-- Filters may be recursive partial objects, one test string, or an AND-array of test strings.
-- Test strings optionally start with a direct field name, for example "name*=home" or ">=10".
-- Both inputs and the output are already-decoded Lua values.

local function array_length(value, label)
	if type(value) ~= "table" then
		error(label .. " must be an array")
	end

	local length = 0
	for key, _ in pairs(value) do
		if type(key) ~= "number" or key ~= math.floor(key) or key < 1 then
			error(label .. " must contain only positive integer keys")
		end
		if key > length then
			length = key
		end
	end

	for index = 1, length do
		if value[index] == nil then
			error(label .. " item '" .. tostring(index) .. "' is nil")
		end
	end

	return length
end

local function is_array(value)
	if type(value) ~= "table" then return false end
	local length = 0
	for key, _ in pairs(value) do
		if type(key) ~= "number" or key ~= math.floor(key) or key < 1 then return false end
		if key > length then length = key end
	end
	for index = 1, length do
		if value[index] == nil then return false end
	end
	return true
end

local function parse_operand(text)
	local trimmed = text:match("^%s*(.-)%s*$")
	local number = tonumber(trimmed)
	if number ~= nil then return number end
	if trimmed == "true" then return true end
	if trimmed == "false" then return false end
	return text
end

local function parse_test(expression)
	if type(expression) ~= "string" then
		error("filter tests must be strings")
	end

	local operators = { "!=", "^=", "$=", "*=", ">=", "<=", ">", "<" }
	local best_position = nil
	local best_operator = nil
	for _, operator in ipairs(operators) do
		local position = expression:find(operator, 1, true)
		if position ~= nil and (best_position == nil or position < best_position) then
			best_position = position
			best_operator = operator
		end
	end
	if best_position == nil then
		error("invalid filter test '" .. expression .. "'")
	end

	local field = expression:sub(1, best_position - 1):match("^%s*(.-)%s*$")
	local operand_text = expression:sub(best_position + #best_operator)
	if operand_text == "" then
		error("filter test '" .. expression .. "' is missing an operand")
	end

	return {
		field = field,
		operator = best_operator,
		operand = (best_operator == "^=" or best_operator == "$=" or best_operator == "*=")
			and operand_text or parse_operand(operand_text),
	}
end

local function apply_test(candidate, test)
	local value = candidate
	if test.field ~= "" then
		if type(candidate) ~= "table" then
			error("filter field '" .. test.field .. "' requires an object item")
		end
		value = candidate[test.field]
		if value == nil then return false end
	end

	local operator = test.operator
	if operator == "!=" then
		if type(value) == "table" or type(test.operand) == "table" then
			error("operator != requires primitive values")
		end
		return value ~= test.operand
	end
	if operator == "^=" or operator == "$=" or operator == "*=" then
		if type(value) ~= "string" then
			error("operator " .. operator .. " requires a string value")
		end
		local operand = test.operand
		if operator == "^=" then return value:sub(1, #operand) == operand end
		if operator == "$=" then return operand == "" or value:sub(-#operand) == operand end
		return value:find(operand, 1, true) ~= nil
	end
	if type(value) ~= "number" or type(test.operand) ~= "number" then
		error("operator " .. operator .. " requires numeric values")
	end
	if operator == ">" then return value > test.operand end
	if operator == "<" then return value < test.operand end
	if operator == ">=" then return value >= test.operand end
	return value <= test.operand
end

local function validate_partial_object(value)
	for key, nested_value in pairs(value) do
		if type(key) ~= "string" then error("filter objects must contain only string keys") end
		if type(nested_value) == "table" then validate_partial_object(nested_value) end
	end
end

local function partial_match(value, expected)
	if type(expected) ~= "table" then return value == expected end
	if type(value) ~= "table" then return false end
	for key, nested_expected in pairs(expected) do
		if not partial_match(value[key], nested_expected) then return false end
	end
	return true
end

local function compile_filter(filter)
	if type(filter) == "string" then
		local test = parse_test(filter)
		return function(item) return apply_test(item, test) end
	end
	if type(filter) ~= "table" then
		error("filter must be an object, a test string, or an array of test strings")
	end
	if is_array(filter) and #filter > 0 then
		local tests = {}
		for index, expression in ipairs(filter) do
			if type(expression) ~= "string" then
				error("filter[" .. tostring(index) .. "] must be a test string")
			end
			tests[index] = parse_test(expression)
		end
		return function(item)
			for _, test in ipairs(tests) do
				if not apply_test(item, test) then return false end
			end
			return true
		end
	end
	validate_partial_object(filter)
	return function(item)
		if type(item) ~= "table" then error("partial-object filters require object items") end
		return partial_match(item, filter)
	end
end

if not inputs.active[1] then
	error("items is not connected")
end
if not inputs.active[2] then
	error("filter is not connected")
end

local items = inputs[1]
local filter = inputs[2]
local count = array_length(items, "items")
local item_matches = compile_filter(filter)

local result = {}
for index = 1, count do
	local item = items[index]
	if item_matches(item) then
		result[#result + 1] = item
	end
end

outputs[1] = result
