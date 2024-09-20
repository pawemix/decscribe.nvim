local M = {}

---@class (exact) decscribe.diff.Removal

---@type decscribe.diff.Removal
M.Removal = {}

---@param values any[]
---@return string[] sha256 digests
local function to_digest_lines(values)
	local out = ""
	for _, val in ipairs(values) do
		out = out .. vim.fn.sha256(vim.inspect(val)) .. "\n"
	end
	return out
end

---@generic Value
---@param before Value[]
---@param after Value[]
local function diff_list(before, after)
	local before_hashes = to_digest_lines(before)
	local after_hashes = to_digest_lines(after)

	local hunks = vim.diff(
		before_hashes, after_hashes, { linematch = true, result_type = "indices"})
	local out = {}
	---@cast hunks integer[][]
	for _, hunk in ipairs(hunks) do
		assert(#hunk == 4)
		local start1, count1, start2, count2 = unpack(hunk)
		-- removal:
		if count1 > 0 and count2 == 0 then
			for idx = start1, start1 + count1 - 1 do
				out[idx] = M.Removal
			end
			goto continue
		end
		-- addition:
		if count1 == 0 and count2 > 0 then
			error("TODO")
			goto continue
		end
		-- block change:
		if count1 == count2 then
			assert(start1 == start2, "Block moves not handled yet!")
			for idx = start1, start1 + count1 - 1 do
				out[idx] = M.diff(before[idx], after[idx])
			end
			goto continue
		end
		error(string.format("Cannot handle hunk %s!", vim.inspect(hunk)))
    ::continue::
	end
	return out
end

---Compare two instances of the same data structure and produce a diff of
---changed attributes.
---@generic Value
---@param before Value
---@param after Value
---@return Value|table|decscribe.diff.Removal
function M.diff(before, after)
	-- If the types differ, just return the new value:
	if(type(before) ~= type(after)) then return after end
	-- The types are the same, but they're primitives - return the new value:
	if(type(before) ~= "table") then return after end
	-- gather a superset of non-index keys
	local keys = {}
	for key, _ in pairs(before) do keys[key] = true end
	for key, _ in pairs(after) do keys[key] = true end
	for idx = 1, #before do keys[idx] = nil end
	for idx = 1, #after do keys[idx] = nil end

	local out = diff_list(before, after)

	for key, _ in pairs(keys) do
		local before_value = before[key]
		local after_value = after[key]
		--
		if type(before_value) ~= type(after_value) then
			if after_value ~= nil then
				out[key] = after_value
			else
				out[key] = M.Removal
			end
			goto continue
		end
		-- At that point, both values have the same type.
		if type(before_value) ~= "table" then
			if before_value ~= after_value then out[key] = after_value end
			goto continue
		end
		-- At that point, both values are tables.
		if vim.deep_equal(before_value, after_value) then
			goto continue
		end
		-- Try to detect removal of values from a list:
		if #before ~= #after then

			goto continue
		end
		out[key] =  M.diff(before_value, after_value)
		--
		::continue::
	end
	return out
end

return M
