local M = {}

---@class (exact) ical.uid_t

---@alias ical.ical_t string

---@class (exact) ical.vtodo_t
---@field summary string?
---@field description string?
---@field completed boolean
---@field priority number?
local vtodo_t = {}

local ICAL_PROP_NAMES = {
	-- TODO: insert BEGIN:VCALENDAR
	"VERSION",
	"PRODID",
	"BEGIN", -- TODO: replace with BEGIN:VTODO
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
	"END", -- TODO: replace END:VTODO
	-- TODO: insert END:VCALENDAR
}

---@enum ical.priority_t
M.priority_t = {
	undefined = 0,
	tasks_org_high = 1,
	tasks_org_medium = 5,
	tasks_org_low = 9,
}

--- priority_t:
--- 0 = undefined
--- 1 = highest
--- (1-4 = CUA "HIGH")
--- (5 = normal or CUA "MEDIUM")
--- (6-9 = CUA "LOW")
--- 9 = lowest
-- (tasks.org: 9, 5, 1, ???

local UID_LENGTH = 19
local UID_FORMAT = "%0" .. UID_LENGTH .. "d"
local UID_MAX = math.pow(10, UID_LENGTH) - 1

---@param uids ical.uid_t[]
---@param seed number?
---@return ical.uid_t
function M.generate_uid(uids, seed)
	math.randomseed(seed or os.clock() * 1000000)
	while true do
		local uid = string.format(UID_FORMAT, math.random(0, UID_MAX))
		-- uid has to be unique in given context; also small risk of being negative
		if not vim.tbl_contains(uids, uid) and not vim.startswith(uid, "-") then
			---@diagnostic disable-next-line: return-type-mismatch
			return uid
		end
	end
end

---@param uid ical.uid_t
---@param vtodo ical.vtodo_t
---@return ical.ical_t
function M.create_ical_vtodo(uid, vtodo)
	local created_stamp = os.date("!%Y%m%dT%H%M%SZ")

	local priority = vtodo.priority or M.priority_t.undefined
	local description = vtodo.description:gsub(
		"[\r\n]",
		function(s) return "\\" .. s end
	) or ""
	-- TODO: summary: enforce RFC 5545 compliance (no newlines, no semicolons,
	-- 75 chars maximum)
	local summary = vtodo.summary:gsub("[\r\n;]", ". ") or ""

	return table.concat({
		"BEGIN:VCALENDAR",
		"VERSION:2.0",
		"BEGIN:VTODO",
		"PRODID:decscribe",
		-- "PRODID:+//IDN bitfire.at//ical4android", -- NOTE: tasks.org's PRODID
		"DTSTAMP:" .. created_stamp,
		"UID:" .. uid,
		"CREATED:" .. created_stamp, -- TODO: parameterize? vtodo.created
		"LAST-MODIFIED:" .. created_stamp,
		"SUMMARY:" .. summary,
		"DESCRIPTION:" .. description,
		"PRIORITY:" .. priority,
		"STATUS:" .. (vtodo.completed and "COMPLETED" or "NEEDS-ACTION"),
		-- "CATEGORIES:", -- TODO
		-- "X-APPLE-SORT-ORDER:123456789",
		-- RELATED-TO;RELTYPE=PARENT:<uid>
		"COMPLETED:" .. created_stamp,
		"PERCENT-COMPLETE:" .. (vtodo.completed and "100" or "0"),
		"END:VTODO",
		"END:VCALENDAR",
	}, "\r\n")
end

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

	return prop_value, prop_name_idx + 2, prop_value_start_idx, prop_value_end_idx
end

return M
