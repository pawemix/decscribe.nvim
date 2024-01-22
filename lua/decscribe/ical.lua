local M = {}

---@alias
local ICAL_PROP_NAMES = {
	"VERSION",
	"PRODID",
	"BEGIN",
	"DTSTAMP",
	"UID",
	"CREATED",
	"LAST-MODIFIED",
	"SUMMARY",
	"DESCRIPTION",
	"PRIORITY",
	"STATUS",
	"X-APPLE-SORT-ORDER",
	"COMPLETED",
	"PERCENT-COMPLETE",
}

---Returns nothing (`nil`) if there were no matches.
---@param ical Ical
---@param prop_name string
---@return string? prop_value
---@return integer? prop_name_idx
---@return integer? prop_value_start_idx
---@return integer? prop_value_end_idx
function M.find_ical_prop(ical, prop_name)
	-- TODO: What if the property is at the beginning?
	-- It won't be prefixed with \r\n.
	local prop_pat = ("\r\n%s:"):format(prop_name)
	local prop_name_idx = ical:find(prop_pat, 1, true)

	-- When no matches:
	if prop_name_idx == nil then return end

	local prop_value_start_idx = prop_name_idx + #prop_pat

	local next_prop_name_idx = #ical
	for _, pname in ipairs(ICAL_PROP_NAMES) do
		local idx = ical:find(("\r\n%s:"):format(pname), prop_value_start_idx, true)
		if idx then next_prop_name_idx = math.min(next_prop_name_idx, idx) end
	end
	-- TODO: What if the searched property is the last one?
	assert(next_prop_name_idx < #ical)

	local prop_value_end_idx = next_prop_name_idx - 1
	local prop_value = ical:sub(prop_value_start_idx, prop_value_end_idx)

	return prop_value, prop_name_idx, prop_value_start_idx, prop_value_end_idx
end

return M
