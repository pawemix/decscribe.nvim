local ic = require("decscribe.ical")
local ts = require("decscribe.tasks")

local M = {}

---@class (exact) decscribe.UiFacade
---@field buf_get_lines fun(start: integer, end_: integer): string[]
---@field buf_set_lines fun(start: integer, end_: integer, lines: string[])
---@field buf_set_opt fun(opt_name: string, value: any)

---@class (exact) decscribe.State
---@field main_buf_nr integer?
---@field tasks tasks.Tasks
---@field lines string[]
---@field curr_coll_id string?
---@field decsync_dir string?
---@field tzid string? ICalendar timezone info, e.g.: "America/Chicago"

---XXX: Indices in `todos` will change - any data referring to those indices
---may break unless properly handled.
---@param state decscribe.State
---@param idx integer
---@param params decscribe.WriteBufferParams
---@return ical.uid_t to_be_removed
local function on_line_removed(state, idx, params)
	local deleted_task = state.tasks:delete_at(idx)
	assert(
		deleted_task,
		"Tried deleting task at index " .. idx .. "but there was nothing there"
	)
	return deleted_task.uid
end

---XXX: Indices in `todos` will change - any data referring to those indices
---may break unless properly handled.
---@param state decscribe.State
---@param idx integer
---@param line string
---@param params decscribe.WriteBufferParams
---@return ical.uid_t added_task_uid
---@return ical.ical_t added_task_ical
local function on_line_added(state, idx, line, params)
	params = params or {}
	local uid = ic.generate_uid(state.tasks:uids(), params.seed)
	local vtodo = ic.parse_md_line(line)
	-- TODO: add a diagnostic to the line
	assert(vtodo, "Invalid line while adding new entry")

	local ical = ic.create_ical_vtodo(uid, vtodo, {
		fresh_timestamp = params.fresh_timestamp,
		tzid = state.tzid,
	})
	---@type tasks.Task
	local todo = {
		uid = uid,
		collection = state.curr_coll_id,
		vtodo = vtodo,
		ical = ical,
	}
	state.tasks:add_at(idx, todo)
	return uid, ical
end

---@param state decscribe.State
---@param idx integer
---@param new_line string
---@param params decscribe.WriteBufferParams
---@return ical.uid_t?, ical.ical_t?
local function on_line_changed(state, idx, new_line, params)
	local changed_todo = state.tasks:get_at(idx)
	assert(
		changed_todo,
		"Expected an existing task at " .. idx .. " but found nothing"
	)

	local new_vtodo = ic.parse_md_line(new_line)
	assert(new_vtodo)

	if vim.deep_equal(changed_todo.vtodo, new_vtodo) then return end

	-- XXX: any vtodo properties, that cannot be evaluated from line parsing, will
	-- be lost, unless we explicitly assign them! e.g. parent vtodo uid:
	new_vtodo.parent_uid = new_vtodo.parent_uid or changed_todo.vtodo.parent_uid
	changed_todo.vtodo = new_vtodo

	state.tasks:update_at(idx, changed_todo.vtodo)
	local uid = changed_todo.uid
	local ical = changed_todo.ical
	local vtodo = changed_todo.vtodo

	-- TODO: what if as a user I e.g. write into my description "STATUS:NEEDS-ACTION" string? will I inject metadata into the iCal?

	---@type table<string, string|false|{ opts: decscribe.ical.IcalOptions, value: string}>
	---a dict on what fields to change; if value is a string, the field should be
	---updated to that; if it's `false`, the field should be removed if present
	local changes = {}

	local new_status = vtodo.completed and "COMPLETED" or "NEEDS-ACTION"
	changes["STATUS"] = new_status

	---@type string|false
	local summary = vtodo.summary or false
	if summary == "" then summary = false end
	changes["SUMMARY"] = summary

	local categories = vtodo.categories
	if not categories or #categories == 0 then
		changes["CATEGORIES"] = false
	else
		local new_cats = { unpack(categories) }
		-- NOTE: there is a convention (or at least tasks.org follows it) to sort
		-- categories alphabetically:
		table.sort(new_cats)
		local new_cats_str = table.concat(new_cats, ",")
		changes["CATEGORIES"] = new_cats_str
	end

	local priority = vtodo.priority
	if not priority or priority == ic.priority_t.undefined then
		changes["PRIORITY"] = false
	else
		changes["PRIORITY"] = tostring(priority)
	end

	local parent_uid = vtodo.parent_uid
	if parent_uid then
		changes["RELATED-TO"] =
			{ value = parent_uid, opts = { RELTYPE = "PARENT" } }
	end

	local dtstart = vtodo.dtstart
	if not dtstart then
		changes["DTSTART"] = false
	elseif dtstart.precision == ic.DatePrecision.Date then
		local dtstart_date_str = os.date("%Y%m%d", dtstart.timestamp)
		---@cast dtstart_date_str string
		changes["DTSTART"] = { value = dtstart_date_str, opts = { VALUE = "DATE" } }
	elseif dtstart.precision == ic.DatePrecision.DateTime then
		local dtstart_date_str = os.date("%Y%m%dT%H%M%S", dtstart.timestamp)
		local tzid = state.tzid
		assert(tzid, "Cannot write timezone-specific datetime without tzid")
		---@cast dtstart_date_str string
		changes["DTSTART"] = { value = dtstart_date_str, opts = { TZID = tzid } }
	else
		error("Unhandled state of DTSTART property")
	end

	local due = vtodo.due
	if not due then
		changes["DUE"] = false
	elseif due.precision == ic.DatePrecision.Date then
		local due_date_str = os.date("%Y%m%d", vtodo.due.timestamp)
		---@cast due_date_str string
		changes["DUE"] = { value = due_date_str, opts = { VALUE = "DATE" } }
	elseif due.precision == ic.DatePrecision.DateTime then
		local due_date_str = os.date("%Y%m%dT%H%M%S", due.timestamp)
		local tzid = state.tzid
		assert(tzid, "Cannot write timezone-specific datetime without tzid")
		---@cast due_date_str string
		changes["DUE"] = { value = due_date_str, opts = { TZID = tzid } }
	else
		error("Unhandled state of DUE property")
	end

	local ical_entries = ic.ical_parse(ical)

	-- remove all entries marked for deletion:
	for i = #ical_entries, 1, -1 do
		local key = ical_entries[i].key
		if changes[key] == false then
			changes[key] = nil
			table.remove(ical_entries, i)
		end
	end
	-- discard all deletion changes that weren't applied due to the entry not
	-- being there at all:
	for key, value in pairs(changes) do
		if value == false then changes[key] = nil end
	end

	-- update all existing entries:
	for _, entry in ipairs(ical_entries) do
		local change = changes[entry.key]
		if change ~= nil then
			if type(change) == "string" then
				entry.value = change
			elseif type(change) == "table" then
				entry.value = change.value
				entry.opts = change.opts -- TODO: overwrite or merge?
			else
				error("unexpected type of change: " .. vim.inspect(change))
			end
			changes[entry.key] = nil
		end
	end

	-- insert new entries right before "END:VTODO"
	for i, entry in ipairs(ical_entries) do
		if entry.key == "END" and entry.value == "VTODO" then
			for key, change in pairs(changes) do
				---@type decscribe.ical.IcalEntry?
				local new_entry = nil
				if type(change) == "string" then
					new_entry = { key = key, value = change }
				elseif type(change) == "table" then
					new_entry = { key = key, value = change.value, opts = change.opts }
				else
					error("unexpected type of change: " .. vim.inspect(change))
				end
				table.insert(ical_entries, i, new_entry)
			end
			break
		end
	end
	assert(#changes == 0, "some changes were unexpectedly not applied")

	local out_ical = ic.ical_show(ical_entries)
	return uid, out_ical
end

---@class (exact) decscribe.OpenBufferParams
---@field decsync_dir string
---@field collection_label decscribe.CollLabel
---@field list_collections_fn fun(ds_dir_path: string): decscribe.Collections

---@param state decscribe.State
---@param params decscribe.OpenBufferParams
function M.open_buffer(state, params)
	state.decsync_dir = params.decsync_dir
	if not state.decsync_dir then
		vim.notify_once(
			"Decsync directory (arg #1) has to be given",
			vim.log.levels.ERROR
		)
		return
	end
	-- expand potential path shortcuts like '~':
	state.decsync_dir = vim.fn.expand(state.decsync_dir)

	local coll_name = params.collection_label
	if not coll_name then
		vim.notify_once(
			"Collection name (arg #2) has to be given",
			vim.log.levels.ERROR
		)
		return
	end
	local colls = params.list_collections_fn(state.decsync_dir)
	if not colls[coll_name] then
		local msg = ("Collection '%s' does not exist."):format(coll_name)
		local coll_names = vim.tbl_keys(colls)
		if #coll_names > 0 then
			local function enquote(s) return "'" .. s .. "'" end
			msg = msg .. "\nAvailable collections: "
			msg = msg .. table.concat(vim.tbl_map(enquote, coll_names), ", ")
		end
		vim.notify(msg, vim.log.levels.ERROR)
		return
	end
	state.curr_coll_id = colls[coll_name]

	-- FIXME: when rerunning the command and the buffer exists, don't create new
	-- buffer

	-- initialize and configure the buffer
	if state.main_buf_nr == nil then
		state.main_buf_nr = vim.api.nvim_create_buf(true, false)

		vim.api.nvim_buf_set_name(
			state.main_buf_nr,
			"decscribe://" .. state.decsync_dir
		)
		vim.api.nvim_buf_set_option(state.main_buf_nr, "filetype", "decscribe")
		vim.api.nvim_buf_set_option(state.main_buf_nr, "buftype", "acwrite")
		-- vim.api.nvim_buf_set_option(bufnr, "number", false)
		-- vim.api.nvim_buf_set_option(bufnr, "cursorline", false)
		-- vim.cmd [[setlocal omnifunc=v:lua.octo_omnifunc]]
		-- vim.cmd [[setlocal conceallevel=2]]
		-- vim.cmd [[setlocal signcolumn=yes]]

		-- TODO: apply buf-local mappings (e.g. <C-Space> on checking todos)
	end

	if vim.api.nvim_get_current_buf() ~= state.main_buf_nr then
		vim.api.nvim_set_current_buf(state.main_buf_nr)
	end
end

---@class decscribe.ReadBufferParamsFP
---@field icals table<ical.uid_t, ical.ical_t>

---@class (exact) decscribe.ReadBufferParamsOP
---@field db_retrieve_icals fun(): table<ical.uid_t, ical.ical_t>
---@field ui decscribe.UiFacade

---@alias decscribe.ReadBufferParams
---| decscribe.ReadBufferParamsOP
---| decscribe.ReadBufferParamsFP

---@param state decscribe.State
---@param params decscribe.ReadBufferParams
---@return string[] lines
function M.read_buffer(state, params)
	-- tasklist has to be recreated from scratch, so that there are no leftovers,
	-- e.g. from a different collection/dsdir
	state.tasks = ts.Tasks:new()

	local uid_to_icals = params.icals or params.db_retrieve_icals()

	for todo_uid, todo_ical in pairs(uid_to_icals) do
		---@type ical.vtodo_t
		local vtodo = ic.vtodo_from_ical(todo_ical)

		---@type tasks.Task
		local todo = {
			vtodo = vtodo,
			ical = todo_ical,
			uid = todo_uid,
			collection = state.curr_coll_id,
		}

		state.tasks:add(todo_uid, todo)
	end

	state.lines = {}
	for _, task in ipairs(state.tasks:to_list()) do
		local line = ic.to_md_line(task.vtodo)
		if line then table.insert(state.lines, line) end
	end

	-- initially fill the buffer with initial data:
	if (params.ui or {}).buf_set_lines and (params.ui or {}).buf_set_opt then
		params.ui.buf_set_lines(0, -1, state.lines)
		params.ui.buf_set_opt("modified", false)
	end
	return state.lines
end

---@class decscribe.WriteBufferParams
---@field new_lines string[]
---@field fresh_timestamp? integer
---@field seed? integer used for random operations

---@class (exact) decscribe.WriteBufferOutcome
---@field changes table<ical.uid_t, ical.ical_t|false>

---@param state decscribe.State
---@param params decscribe.WriteBufferParams
---@return decscribe.WriteBufferOutcome
function M.write_buffer(state, params)
	local old_contents = state.lines
	local new_contents = params.new_lines
	local hunks = vim.diff(
		table.concat(old_contents, "\n"),
		table.concat(new_contents, "\n"),
		{ result_type = "indices" }
	)
	assert(type(hunks) == "table", "Decscribe: unexpected diff output")
	---@type decscribe.WriteBufferOutcome
	local out = { changes = {} }
	local lines_to_affect = {}
	for _, hunk in ipairs(hunks) do
		local old_start, old_count, new_start, new_count = unpack(hunk)

		if old_count == 0 and new_count == 0 then
			error('It is not possible that "absence of lines" moved.')
		end

		local start
		local count
		-- something was added:
		if old_count == 0 and new_count > 0 then
			--
			-- NOTE: vim.diff() provides, which index the hunk will move into,
			-- based on *the previous hunks*. E.g. given a one-line deletion at
			-- #100 and a two-line deletion at #200, the hunks will be:
			--
			-- { 100, 1, 99, 0 } and { 200, 2, >>197<<, 0 }
			--
			-- Therefore, the second hunk's destination index takes into account
			-- the one line deleted in the first hunk.
			--
			-- NOTE: This is not yet utilized here, but may be useful when
			-- complexity of this logic grows.
			--
			start = new_start
			count = new_count
			for idx = start, start + count - 1 do
				table.insert(lines_to_affect, { idx = idx, line = new_contents[idx] })
			end
		-- something was removed:
		elseif old_count > 0 and new_count == 0 then
			start = old_start
			count = old_count
			for idx = start, start + count - 1 do
				table.insert(lines_to_affect, { idx = idx, line = nil })
			end
		-- something changed, size remained the same:
		elseif old_count == new_count and old_start == new_start then
			start = old_start -- since they're both the same anyway
			count = old_count -- since they're both the same anyway
			assert(count > 0, "decscribe: diff count in this hunk cannot be 0")
			for idx = start, start + count - 1 do
				local new_line = new_contents[idx]
				local new_uid, new_ical = on_line_changed(state, idx, new_line, params)
				if new_uid and new_ical then
					assert(
						not out.changes[new_uid],
						"when collecting new tasks to create, some have colliding UIDs"
					)
					out.changes[new_uid] = new_ical
				end
			end
		-- different scenario
		else
			error("decscribe: some changes could not get handled")
		end
	end
	-- sort pending changes in reversed order to not break indices when
	-- removing/adding entries:
	table.sort(lines_to_affect, function(a, b) return a.idx > b.idx end)
	-- apply pending changes
	for _, change in ipairs(lines_to_affect) do
		local idx = change.idx
		if change.line == nil then
			local removed_uid = on_line_removed(state, idx, params)
			assert(type(removed_uid) == "string")
			out.changes[removed_uid] = false
		else
			local added_uid, added_ical =
				on_line_added(state, idx, change.line, params)
			assert(
				not out.changes[added_uid],
				"when collecting new tasks to create, some have colliding UIDs"
			)
			out.changes[added_uid] = added_ical
		end
	end

	-- updating succeeded
	state.lines = new_contents

	return out
end

---@alias decscribe.CollLabel string
---@alias decscribe.CollId string
---@alias decscribe.Collections table<decscribe.CollLabel, decscribe.CollId>

---@class (exact) decscribe.CompleteCommandlineParams
---@field is_decsync_dir_fn fun(path: string): boolean
---@field list_collections_fn fun(ds_dir_path: string): decscribe.Collections
---@field complete_path_fn fun(path_prefix: string): string[]

---@param arg_lead string
---@param cmd_line string
---@param params decscribe.CompleteCommandlineParams
---@return string[]
function M.complete_commandline(arg_lead, cmd_line, params)
	local cmd_line_comps = vim.split(cmd_line, "%s+")
	-- if this is the 1st argument (besides the cmd), provide path completion:
	if arg_lead == cmd_line_comps[2] then
		return params.complete_path_fn(arg_lead)
	end
	-- otherwise, this is the second argument:
	local ds_dir = vim.fn.expand(cmd_line_comps[2])
	if not params.is_decsync_dir_fn(ds_dir) then return {} end

	local coll_names = vim.tbl_keys(params.list_collections_fn(ds_dir))
	return vim.tbl_filter(
		function(s) return vim.startswith(s, arg_lead) end,
		coll_names
	)
end

return M
