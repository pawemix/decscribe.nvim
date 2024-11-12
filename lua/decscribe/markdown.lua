local dt = require("decscribe.date")
local core = require("decscribe.core")

local M = {}

M.priority2label = {
	[core.Priority.HIGH] = "H",
	[core.Priority.MEDIUM] = "M",
	[core.Priority.LOW] = "L",
}

-- TODO: decode String to Markdown AST which shall be then mapped to Todo. And
-- vice versa. This way Todos can be presented in Markdown in a different
-- fashion customized by user.

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
---@param ancestors decscribe.core.TempRef[]
---@param todos_aggr decscribe.core.TempTodo[]
---@return decscribe.core.TempTodo[]? todos
local function decode_lines(md_lines, ancestors, todos_aggr)
	-- If there are no more lines to decode - finish:
	if md_lines[1] == nil then return todos_aggr end
	--
	local child_indent_str = ("\t"):rep(#ancestors)
	local line = md_lines[1]
	-- If indentation is lower than expected for a sibling - move up a parent:
	if not vim.startswith(line, child_indent_str) then
		table.remove(ancestors)
		return decode_lines(md_lines, ancestors, todos_aggr)
	end
	-- remove child indentation:
	line = line:sub(#child_indent_str + 1)
	-- if a line is blank - discard it:
	if #line:gsub("^%s+", "", 1) == 0 then
		table.remove(md_lines, 1)
		return decode_lines(md_lines, ancestors, todos_aggr)
	end
	-- assume the line to be okay and try to decode the todo:
	local todo = assert(
		decode_line(line), "Could not parse line: '" .. line .. "'!")
	local new_ref = #todos_aggr + 1
	local temp_todo = core.with_ref(todo, new_ref)
	if ancestors[1] ~= nil then temp_todo.parent_ref = ancestors[#ancestors] end
	todos_aggr[new_ref] = temp_todo
	ancestors[#ancestors+1] = new_ref
	table.remove(md_lines, 1)
	return decode_lines(md_lines, ancestors, todos_aggr)
end

---@param md_text string
---@return decscribe.core.TempTodo[]? todos
function M.decode(md_text)
	return decode_lines(vim.split(md_text, "\n"), {}, {})
end

---@param todo decscribe.core.Todo
---@return string
function M.todo2str(todo)
	local line = "- [" .. (todo.completed and "x" or " ") .. "]"

	local dtstart_str = nil
	if todo.dtstart then
		if todo.dtstart.precision == dt.Precision.Date then
			dtstart_str = os.date("%Y-%m-%d", todo.dtstart.timestamp)
		elseif todo.dtstart.precision == dt.Precision.DateTime then
			dtstart_str = os.date("%Y-%m-%d %H:%M", todo.dtstart.timestamp)
		else
			error("Unexpected kind of dtstart date: " .. vim.inspect(todo.dtstart))
		end
	end

	local due_str = nil
	if todo.due then
		if todo.due.precision == dt.Precision.Date then
			due_str = os.date("%Y-%m-%d", todo.due.timestamp)
		elseif todo.due.precision == dt.Precision.DateTime then
			due_str = os.date("%Y-%m-%d %H:%M", todo.due.timestamp)
		else
			error("Unexpected kind of due date: " .. vim.inspect(todo.due))
		end
	end

	if dtstart_str and due_str then
		line = line .. " " .. dtstart_str .. ".." .. due_str
	elseif dtstart_str then
		line = line .. " " .. dtstart_str .. ".."
	elseif due_str then
		line = line .. " " .. due_str
	end

	if todo.priority then
		local prio_char = assert(
			M.priority2label[todo.priority],
			"Unrecognized priority: " .. vim.inspect(todo.priority))
		line = line .. " !" .. prio_char
	end
	if todo.categories and #todo.categories > 0 then
		local function in_colons(s) return ":" .. s .. ":" end
		local categories_str =
			table.concat(vim.tbl_map(in_colons, todo.categories), " ")
		line = line .. " " .. categories_str
	end
	if todo.summary then line = line .. " " .. todo.summary end
	-- TODO: handle newlines (\n as well as \r\n) in summary more elegantly
	line = line:gsub("\r?\n", " ")
	return line
end

return M
