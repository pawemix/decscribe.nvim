local dt = require("decscribe.date")

local M = {}

---@alias decscribe.ical.Uid string
---@alias decscribe.ical.String string
---@alias decscribe.ical.Options { [string]: string }

---@class decscribe.ical.Entry
---@field key string
---@field value string
---@field opts? decscribe.ical.Options

---@alias decscribe.ical.Document decscribe.ical.Entry[]

---@class (exact) decscribe.ical.Vtodo
---@field summary string?
---@field description string?
---@field completed boolean
---@field priority number?
---@field categories string[]?
---@field parent_uid decscribe.ical.Uid?
---@field due decscribe.date.Date?
---@field dtstart decscribe.date.Date?

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
	"RELATED-TO",
	"X-APPLE-SORT-ORDER",
	"DUE",
	"DTSTART",
	"COMPLETED",
	"PERCENT-COMPLETE",
	"END", -- TODO: replace END:VTODO
	-- TODO: insert END:VCALENDAR
}

---@enum decscribe.ical.Priority
M.Priority = {
	undefined = 0,
	tasks_org_high = 1,
	tasks_org_medium = 5,
	tasks_org_low = 9,
	-- tasks_org_lowest = nil, -- i.e. no PRIORITY prop at all
}

M.labelled_priorities = vim.tbl_add_reverse_lookup({
	H = M.Priority.tasks_org_high,
	M = M.Priority.tasks_org_medium,
	L = M.Priority.tasks_org_low,
})

--- Priority:
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

---@param uids decscribe.ical.Uid[]
---@param seed number?
---@return decscribe.ical.Uid
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

---@class ical.CreateIcalVtodo.Params
---@field fresh_timestamp? integer used for "created at" properties etc.
---@field tzid? string time zone id

---@param uid decscribe.ical.Uid
---@param vtodo decscribe.ical.Vtodo
---@param params? ical.CreateIcalVtodo.Params
---@return decscribe.ical.String
function M.create_ical_vtodo(uid, vtodo, params)
	params = params or {}
	local created_stamp = os.date("!%Y%m%dT%H%M%SZ", params.fresh_timestamp)

	local priority = vtodo.priority or M.Priority.undefined

	local description = nil
	if type(vtodo.description) == "string" then
		description = vtodo.description:gsub(
			"[\r\n]",
			function(s) return "\\" .. s end
		)
	end
	-- TODO: summary: enforce RFC 5545 compliance (no newlines, no semicolons,
	-- 75 chars maximum)
	local summary = vtodo.summary:gsub("[\r\n;]", ". ") or ""

	-- TODO: enforce no colons nor CRLFs in category names
	local categories = table.concat(vtodo.categories or {}, ",")

	---@type table|string
	local parent_uid_entry = {}
	if vtodo.parent_uid then
		parent_uid_entry = "RELATED-TO;RELTYPE=PARENT:" .. vtodo.parent_uid
	end

	local due_entry = nil
	if vtodo.due then
		if vtodo.due.precision == dt.Precision.Date then
			due_entry = "DUE;VALUE=DATE:" .. os.date("%Y%m%d", vtodo.due.timestamp)
		elseif vtodo.due.precision == dt.Precision.DateTime then
			assert(params.tzid, "TZID required to print due date but not given")
			local due_date_str = os.date("%Y%m%dT%H%M%S", vtodo.due.timestamp)
			due_entry = "DUE;TZID=" .. params.tzid .. ":" .. due_date_str
		else
			error("Unexpected value of DatePrecision")
		end
	end

	---@type decscribe.ical.Entry
	local dtstart_entry = nil
	if vtodo.dtstart then
		if vtodo.dtstart.precision == dt.Precision.Date then
			local dtstart_date_str = os.date("%Y%m%d", vtodo.dtstart.timestamp)
			dtstart_entry = {
				key = "DTSTART",
				opts = { VALUE = "DATE" },
				---@cast dtstart_date_str string
				value = dtstart_date_str,
			}
		elseif vtodo.dtstart.precision == dt.Precision.DateTime then
			assert(params.tzid, "TZID required to print due date but not given")
			local dtstart_date_str = os.date("%Y%m%dT%H%M%S", vtodo.dtstart.timestamp)
			dtstart_entry = {
				key = "DTSTART",
				opts = { TZID = params.tzid },
				---@cast dtstart_date_str string
				value = dtstart_date_str,
			}
		else
			error("Unexpected value of DatePrecision")
		end
	end
	---@type string?
	local dtstart_entry_str = nil
	if dtstart_entry then
		dtstart_entry_str = M.ical_show({ dtstart_entry })
		dtstart_entry_str = dtstart_entry_str:sub(1, #dtstart_entry_str - 2)
	end

	local out = vim.tbl_flatten({
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
		(description and ("DESCRIPTION:" .. description) or {}),
		"PRIORITY:" .. priority,
		"STATUS:" .. (vtodo.completed and "COMPLETED" or "NEEDS-ACTION"),
		"CATEGORIES:" .. categories,
		-- "X-APPLE-SORT-ORDER:123456789",
		parent_uid_entry,
		"COMPLETED:" .. created_stamp,
		"PERCENT-COMPLETE:" .. (vtodo.completed and "100" or "0"),
		(due_entry or {}),
		(dtstart_entry_str or {}),
		"END:VTODO",
		"END:VCALENDAR",
	})
	return table.concat(out, "\r\n") .. "\r\n"
end

---Returns nothing (`nil`) if there were no matches.
---@param ical decscribe.ical.String
---@param prop_name string
---@return string? prop_value
---@return integer? prop_name_idx
---@return integer? prop_value_start_idx
---@return integer? prop_value_end_idx
function M.find_ical_prop(ical, prop_name)
	-- TODO: What if the property is at the beginning?
	-- It won't be prefixed with \r\n.
	local prop_name_idx = ical:find("\r\n" .. prop_name, 1, true)
	-- When no matches:
	if prop_name_idx == nil then return end

	-- ignore leading CRLF:
	prop_name_idx = prop_name_idx + 2

	-- idx + prop name + separator char (usually ":"):
	local prop_value_start_idx = prop_name_idx + #prop_name + 1

	local next_prop_name_idx = #ical
	for _, pname in ipairs(ICAL_PROP_NAMES) do
		local idx = ical:find("\r\n" .. pname, prop_value_start_idx, true)
		if idx then next_prop_name_idx = math.min(next_prop_name_idx, idx) end
	end
	-- TODO: What if the searched property is the last one?
	assert(next_prop_name_idx < #ical)

	-- NOTE: next_prop_name_idx points at CR in CRLF *before* the said prop name:
	local prop_value_end_idx = next_prop_name_idx - 1
	local prop_value = ical:sub(prop_value_start_idx, prop_value_end_idx)

	return prop_value, prop_name_idx, prop_value_start_idx, prop_value_end_idx
end

---@return decscribe.ical.String
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

---@return decscribe.ical.String
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

---@param ical decscribe.ical.String
---@param prop_name string
---@param prop_value string
---@return decscribe.ical.String new_ical
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
	return insert_ical_prop(ical, prop_name, prop_value)
end

---@return decscribe.ical.Vtodo?
function M.parse_md_line(line)
	local checkbox_heading = line:match("^[-*]%s+[[][ x][]]%s+")
	-- there should always be a checkbox:
	if not checkbox_heading then return nil end
	-- TODO: handle more invalid entries

	local completed = checkbox_heading:match("x") ~= nil

	line = line:sub(#checkbox_heading + 1)

	---@type decscribe.date.Date?
	local dtstart = nil

	local _, dts_date_end, dts_year, dts_month, dts_day, dts_hour, dts_min =
		line:find("^(%d%d%d%d)[-](%d%d)[-](%d%d)%s+(%d%d):(%d%d)[.][.]%s*")
	if dts_date_end then
		line = line:sub(dts_date_end + 1)
		local dts_timestamp = os.time({
			year = dts_year,
			month = dts_month,
			day = dts_day,
			hour = dts_hour,
			min = dts_min,
		})
		dtstart = { timestamp = dts_timestamp, precision = dt.Precision.DateTime }
	end

	if not dtstart then
		_, dts_date_end, dts_year, dts_month, dts_day =
			line:find("^(%d%d%d%d)[-](%d%d)[-](%d%d)[.][.]%s*")
		if dts_date_end then
			line = line:sub(dts_date_end + 1)
			local dts_timestamp =
				os.time({ year = dts_year, month = dts_month, day = dts_day })
			dtstart = { timestamp = dts_timestamp, precision = dt.Precision.Date }
		end
	end

	---@type decscribe.date.Date?
	local due = nil
	local _, due_date_end, year, month, day =
		line:find("^(%d%d%d%d)[-](%d%d)[-](%d%d)%s*")
	if due_date_end then
		line = line:sub(due_date_end + 1)
		local timestamp = os.time({ year = year, month = month, day = day })
		due = { timestamp = timestamp, precision = dt.Precision.Date }
	end
	-- FIXME: space between date and time not enforced here,
	-- i.e. e.g. "2024-06-1212:36" is parsed as proper datetime
	local _, due_time_end, hour, min = line:find("^(%d%d):(%d%d)%s*")
	if due_date_end and due_time_end then
		line = line:sub(due_time_end + 1)
		local timestamp = os.time({
			year = year,
			month = month,
			day = day,
			hour = hour,
			min = min,
			sec = 0,
		})
		due = { timestamp = timestamp, precision = dt.Precision.DateTime }
	end

	local priority = nil
	local _, prio_end, prio = line:find("^!([0-9HML])%s*")
	if tonumber(prio) then
		priority = tonumber(prio)
		line = line:sub(prio_end + 1)
	elseif prio then
		priority = M.labelled_priorities[prio]
		line = line:sub(prio_end + 1)
	end

	local categories = {}
	while true do
		local cat_start, cat_end, cat = line:find("^:([-_%a]+):%s*")
		if not cat_start then break end
		table.insert(categories, cat)
		line = line:sub(cat_end + 1)
	end

	---@type decscribe.ical.Vtodo
	local vtodo = {
		summary = line,
		completed = completed,
		priority = priority or M.Priority.undefined,
		categories = categories,
		description = nil,
		due = due,
		dtstart = dtstart,
	}

	return vtodo
end

---@param vtodo decscribe.ical.Vtodo
---@return string md_line a markdown line representing the todo entry
function M.to_md_line(vtodo)
	local line = "- [" .. (vtodo.completed and "x" or " ") .. "]"

	local dtstart_str = nil
	if vtodo.dtstart then
		if vtodo.dtstart.precision == dt.Precision.Date then
			dtstart_str = os.date("%Y-%m-%d", vtodo.dtstart.timestamp)
		elseif vtodo.dtstart.precision == dt.Precision.DateTime then
			dtstart_str = os.date("%Y-%m-%d %H:%M", vtodo.dtstart.timestamp)
		else
			error("Unexpected kind of dtstart date: " .. vim.inspect(vtodo.dtstart))
		end
	end

	local due_str = nil
	if vtodo.due then
		if vtodo.due.precision == dt.Precision.Date then
			due_str = os.date("%Y-%m-%d", vtodo.due.timestamp)
		elseif vtodo.due.precision == dt.Precision.DateTime then
			due_str = os.date("%Y-%m-%d %H:%M", vtodo.due.timestamp)
		else
			error("Unexpected kind of due date: " .. vim.inspect(vtodo.due))
		end
	end

	if dtstart_str and due_str then
		line = line .. " " .. dtstart_str .. ".." .. due_str
	elseif dtstart_str then
		line = line .. " " .. dtstart_str .. ".."
	elseif due_str then
		line = line .. " " .. due_str
	end

	if vtodo.priority and vtodo.priority ~= M.Priority.undefined then
		local prio_char = M.labelled_priorities[vtodo.priority] or vtodo.priority
		line = line .. " !" .. prio_char
	end
	if vtodo.categories and #vtodo.categories > 0 then
		local function in_colons(s) return ":" .. s .. ":" end
		local categories_str =
			table.concat(vim.tbl_map(in_colons, vtodo.categories), " ")
		line = line .. " " .. categories_str
	end
	if vtodo.summary then line = line .. " " .. vtodo.summary end
	-- TODO: handle newlines (\n as well as \r\n) in summary more elegantly
	line = line:gsub("\r?\n", " ")
	return line
end

---@param date_str string
---@return decscribe.date.Date? precisioned_date_opt or nil if could not parse
local function to_prec_date(date_str)
	local _, _, year, month, day =
		string.find(date_str or "", "^(%d%d%d%d)(%d%d)(%d%d)")
	if year and month and day then
		local timestamp = os.time({ year = year, month = month, day = day })
		return { timestamp = timestamp, precision = dt.Precision.Date }
	else
		return nil -- unexpected format
	end
end

---@param datetime_str string
---@return decscribe.date.Date? precisioned_date_opt nil if could not be parsed
local function to_prec_datetime(datetime_str)
	local _, _, year, month, day, hour, minute =
		string.find(datetime_str or "", "^(%d%d%d%d)(%d%d)(%d%d)T(%d%d)(%d%d)")
	if year and month and day and hour and minute then
		local timestamp = os.time({
			year = year,
			month = month,
			day = day,
			hour = hour,
			min = minute,
		})
		return { timestamp = timestamp, precision = dt.Precision.DateTime }
	else
		return nil -- unexpected format
	end
end

---@param ical decscribe.ical.String
---@return decscribe.ical.Vtodo
function M.vtodo_from_ical(ical)
	local entries = M.ical_parse(ical)

	local vtodo_proto = {}
	for _, entry in ipairs(entries) do
		if entry.key == "END" and entry.value == "VTODO" then
			break
		elseif entry.key == "CATEGORIES" then
			vtodo_proto.categories = vim.split(entry.value, ",", { trimempty = true })
			-- NOTE: there is a convention (or at least tasks.org follows it) to sort
			-- categories alphabetically:
			table.sort(vtodo_proto.categories)
			if #vtodo_proto.categories == 0 then vtodo_proto.categories = nil end
		elseif entry.key == "PRIORITY" then
			vtodo_proto.priority = tonumber(entry.value) or M.Priority.undefined
		elseif entry.key == "STATUS" then
			vtodo_proto.completed = entry.value == "COMPLETED"
		elseif entry.key == "SUMMARY" then
			vtodo_proto.summary = entry.value
		elseif entry.key == "DESCRIPTION" then
			vtodo_proto.description = entry.value
		elseif entry.key == "RELATED-TO" and entry.opts["RELTYPE"] == "PARENT" then
			vtodo_proto.parent_uid = entry.value
		elseif entry.key == "DTSTART" then
			if not entry.opts then
				vim.notify(
					"DTSTART entry without VALUE:" .. vim.inspect(entry),
					vim.log.levels.INFO
				)
			elseif entry.opts["VALUE"] == "DATE" then
				vtodo_proto.dtstart = to_prec_date(entry.value)
			else -- NOTE: without VALUE option treated as 'datetime' case:
				vtodo_proto.dtstart = to_prec_datetime(entry.value)
			end
			assert(vtodo_proto.dtstart)
		elseif entry.key == "DUE" then
			if entry.opts["VALUE"] == "DATE" then
				vtodo_proto.due = to_prec_date(entry.value)
			else -- NOTE: without VALUE option it's treated as 'datetime':
				-- TODO: this is not covered by a test
				vtodo_proto.due = to_prec_datetime(entry.value)
			end
			assert(vtodo_proto.due)
		end
	end

	---@type decscribe.ical.Vtodo
	local vtodo = {
		completed = vtodo_proto.completed,
		priority = vtodo_proto.priority,
		summary = vtodo_proto.summary,
		categories = vtodo_proto.categories,
		description = vtodo_proto.description,
		parent_uid = vtodo_proto.parent_uid,
		due = vtodo_proto.due,
		dtstart = vtodo_proto.dtstart,
	}
	return vtodo
end

---parse an ICal string into a structured list of its properties
---@param ical string
---@return decscribe.ical.Document
function M.ical_parse(ical)
	-- cut out the trailing newline
	if vim.endswith(ical, "\r\n") then ical = string.sub(ical, 1, #ical - 2) end

	---@type decscribe.ical.Document
	local out = {}
	for _, line in
		ipairs(vim.split(ical, "\r\n", { plain = true, trimempty = true }))
	do
		local colon_pos = string.find(line, ":", 1, true)
		if not colon_pos then
			-- append the line to the last added entry's value:
			local last_entry = out[#out]
			assert(last_entry, "Ical starts with free text")
			last_entry.value = last_entry.value .. "\r\n" .. line
		else
			local entry = {}
			entry.value = string.sub(line, colon_pos + 1)
			local header = string.sub(line, 1, colon_pos - 1)
			local header_comps = vim.split(header, ";", { plain = true })
			assert(#header_comps > 0, "empty Ical property header")
			entry.key = table.remove(header_comps, 1)
			if #header_comps > 0 then entry.opts = {} end
			for _, opt_entry in ipairs(header_comps) do
				local opt_entry_comps = vim.split(opt_entry, "=", { plain = true })
				local opt_key = opt_entry_comps[1]
				local opt_value = opt_entry_comps[2]
				if opt_key and opt_value then entry.opts[opt_key] = opt_value end
			end
			table.insert(out, entry)
		end
	end
	return out
end

---show an Ical structure as an ordinary Ical string for external use
---@param ical decscribe.ical.Document
---@return string
function M.ical_show(ical)
	local lines = {}
	for _, entry in ipairs(ical) do
		local header = { entry.key }
		for opt_key, opt_value in pairs(entry.opts or {}) do
			table.insert(header, opt_key .. "=" .. opt_value)
		end
		table.insert(lines, table.concat(header, ";") .. ":" .. entry.value)
	end
	return table.concat(lines, "\r\n") .. "\r\n"
end

return M
