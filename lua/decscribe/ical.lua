local M = {}

---@class (exact) ical.uid_t

---@alias ical.ical_t string

---@class (exact) ical.vtodo_t
---@field summary string?
---@field description string?
---@field completed boolean
---@field priority number?
---@field categories string[]?
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
	"CATEGORIES",
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

	-- TODO: enforce no colons nor CRLFs in category names
	local categories = table.concat(vtodo.categories or {}, ",")

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
		"CATEGORIES:" .. categories,
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

---@return ical.ical_t
local function insert_ical_prop(ical, prop_name, prop_value)
	-- find propname closest to the target propname in the ICAL_PROP_NAMES order,
	-- but still before it:
	local before_prop_order_idx = 1
	for i, pn in ipairs(ICAL_PROP_NAMES) do
		if prop_name == pn then break end
		if ical:find(pn, 1, true) then before_prop_order_idx = i end
	end
	local ical_lines = vim.split(ical, "\r\n")
	-- put the new prop *after* the line where "before prop" resides:
	local before_prop = ICAL_PROP_NAMES[before_prop_order_idx]
	local before_prop_idx = nil
	for idx, line in ipairs(ical_lines) do
		if vim.startswith(line, before_prop) then
			before_prop_idx = idx
			break
		end
	end
	assert(before_prop_idx)
	--
	table.insert(ical_lines, before_prop_idx + 1, prop_name .. ":" .. prop_value)
	-- NOTE: no "\r\n" at the end is needed due to an empty line in input end
	return table.concat(ical_lines, "\r\n")
end

---@return ical.ical_t
local function update_ical_prop(ical, prop_name, prop_value)
	local ical_lines = vim.split(ical, "\r\n")
	for idx, line in ipairs(ical_lines) do
		if vim.startswith(line, prop_name) then
			ical_lines[idx] = prop_name .. ":" .. prop_value
			break
		end
		-- TODO: remove dangling lines of prop value if it was multiline
	end
	-- NOTE: no "\r\n" at the end is needed due to an empty line in input end
	return table.concat(ical_lines, "\r\n")
end

---@return ical.ical_t new_ical
function M.upsert_ical_prop(ical, prop_name, prop_value)
	local ical_lines = vim.split(ical, "\r\n")
	if
		#vim.tbl_filter(
			function(line) return vim.startswith(line, prop_name) end,
			ical_lines
		) > 0
	then
		return update_ical_prop(ical, prop_name, prop_value)
	end
	if true then
		return insert_ical_prop(ical, prop_name, prop_value)
	end
end

---@return ical.vtodo_t?
function M.parse_md_line(line)
	local checkbox_heading = line:match("^[-*]%s+[[][ x][]]%s+")
	-- there should always be a checkbox:
	if not checkbox_heading then return nil end
	-- TODO: handle more invalid entries

	local completed = checkbox_heading:match("x") ~= nil

	local rest = line:sub(#checkbox_heading + 1)

	local categories = {}
	while true do
		local cat_start, cat_end, cat = rest:find("^:([-_%a]+):%s*")
		if not cat_start then break end
		table.insert(categories, cat)
		rest = rest:sub(cat_end + 1)
	end

	---@type ical.vtodo_t
	local vtodo = {
		summary = rest,
		completed = completed,
		priority = M.priority_t.undefined,
		categories = categories,
		description = nil,
	}

	return vtodo
end

return M
