local M = {}

---@param line string
---@return decscribe.core.Todo?
local function decode_line(line)
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
		dtstart =
			{ timestamp = dts_timestamp, precision = M.DatePrecision.DateTime }
	end

	if not dtstart then
		_, dts_date_end, dts_year, dts_month, dts_day =
			line:find("^(%d%d%d%d)[-](%d%d)[-](%d%d)[.][.]%s*")
		if dts_date_end then
			line = line:sub(dts_date_end + 1)
			local dts_timestamp =
				os.time({ year = dts_year, month = dts_month, day = dts_day })
			dtstart = { timestamp = dts_timestamp, precision = M.DatePrecision.Date }
		end
	end

	---@type decscribe.date.Date?
	local due = nil
	local _, due_date_end, year, month, day =
		line:find("^(%d%d%d%d)[-](%d%d)[-](%d%d)%s*")
	if due_date_end then
		line = line:sub(due_date_end + 1)
		local timestamp = os.time({ year = year, month = month, day = day })
		due = { timestamp = timestamp, precision = M.DatePrecision.Date }
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
		due = { timestamp = timestamp, precision = M.DatePrecision.DateTime }
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

	---@type decscribe.core.Todo
	local vtodo = {
		completed = completed or nil,
		summary = line,
		priority = priority,
		categories = #categories > 0 and categories or nil,
		description = nil,
		due = due,
		dtstart = dtstart,
	}

	return vtodo
end


---@param md_lines string[]
---@return decscribe.core.Todo[]? todos
local function decode_lines(md_lines)
	---@type decscribe.core.Todo[]
	local out = {}
	local lines = md_lines
	for idx = 1, #lines do
		local line = lines[idx]
		local todo = decode_line(line)
		if not todo then goto continue end -- TODO: gather decoding errors
		--- if next lines are indented, treat them as children:
		local child_lines = {}
		local child_idx = idx + 1
		while lines[child_idx] and string.sub(lines[child_idx], 1, 1) == "\t" do
			-- remove the minimal indendation to handle more nested subtodos:
			child_lines[#child_lines+1] = string.sub(lines[child_idx], 2)
			child_idx = child_idx + 1
		end
		if #child_lines > 0 then
			todo.subtasks = decode_lines(child_lines)
		end
		out[#out + 1] = todo
		::continue::
	end
	return out
end

---@param md_text string
---@return decscribe.core.Todo[]? todos
function M.decode(md_text)
	return decode_lines(vim.split(md_text, "\n"))
end

return M
