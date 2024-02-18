local M = {}

---@diagnostic disable-next-line: undefined-field
local assert_are_same = assert.are_same
assert(assert_are_same, "testing capabilities are not loaded")

---Like `assert.are_same`, but consider only keys present in both tables.
---@param expected table
---@param actual table
function M.assert_intersections_are_same(expected, actual)
	local actual_subset = {}
	for k, v in pairs(actual) do
		if expected[k] ~= nil then actual_subset[k] = v end
	end
	assert_are_same(expected, actual_subset)
end

return M
