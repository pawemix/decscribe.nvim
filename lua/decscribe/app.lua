local lds = require("decscribe.libdecsync")
local ic = require("decscribe.ical")
local ts = require("decscribe.tasks")

local M = {}

---@type string
local APP_NAME = "decscribe"

---@class (exact) decscribe.State
---@field conn Connection?
---@field main_buf_nr integer?
---@field tasks tasks.Tasks
---@field lines string[]
---@field curr_coll_id string?
---@field decsync_dir string?

---XXX: Indices in `todos` will change - any data referring to those indices
---may break unless properly handled.
---@param state decscribe.State
---@param idx integer
local function on_line_removed(state, idx)
	local deleted_task = state.tasks:delete_at(idx)
	assert(
		deleted_task,
		"Tried deleting task at index " .. idx .. "but there was nothing there"
	)
	---@diagnostic disable-next-line: assign-type-mismatch
	lds.set_entry(state.conn, { "resources", deleted_task.uid }, nil, nil)
end

---XXX: Indices in `todos` will change - any data referring to those indices
---may break unless properly handled.
---@param state decscribe.State
---@param idx integer
---@param line string
local function on_line_added(state, idx, line)
	local uid = ic.generate_uid(state.tasks:uids())
	local vtodo = ic.parse_md_line(line)
	-- TODO: add a diagnostic to the line
	assert(vtodo, "Invalid line while adding new entry")
	local ical = ic.create_ical_vtodo(uid, vtodo)
	---@type tasks.Task
	local todo = {
		uid = uid,
		collection = state.curr_coll_id,
		vtodo = vtodo,
		ical = ical,
	}
	state.tasks:add_at(idx, todo)
	local ical_json = vim.fn.json_encode(ical)
	---@diagnostic disable-next-line: assign-type-mismatch, param-type-mismatch
	lds.set_entry(state.conn, { "resources", uid }, nil, ical_json)
end

---@param state decscribe.State
---@param idx integer
---@param new_line string
local function on_line_changed(state, idx, new_line)
	local changed_todo = state.tasks:get_at(idx)
	assert(
		changed_todo,
		"Expected an existing task at " .. idx .. " but found nothing"
	)
	--
	local new_vtodo = ic.parse_md_line(new_line)
	assert(new_vtodo)
	--
	if not vim.deep_equal(changed_todo.vtodo, new_vtodo) then
		changed_todo.vtodo = vim.tbl_extend("force", changed_todo.vtodo, new_vtodo)
		state.tasks:update_at(idx, changed_todo.vtodo)
		lds.update_todo(state.conn, changed_todo)
	end
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

		vim.api.nvim_buf_set_name(state.main_buf_nr, "decscribe://" .. state.decsync_dir)
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

	M.read_buffer(state)
end

---@param state decscribe.State
function M.read_buffer(state)
	if state.main_buf_nr == nil then return end
	assert(state.main_buf_nr ~= nil)
	assert(state.curr_coll_id)
	assert(state.decsync_dir)

	-- tasklist has to be recreated from scratch, so that there are no leftovers,
	-- e.g. from a different collection/dsdir
	state.tasks = ts.Tasks:new()

	state.conn =
		lds.connect(state.decsync_dir, "tasks", state.curr_coll_id, lds.get_app_id(APP_NAME))

	lds.add_listener(state.conn, { "resources" }, function(path, _, _, value)
		assert(#path == 1, "Unexpected path length while reading updated entry")
		---@type ical.uid_t
		---@diagnostic disable-next-line: assign-type-mismatch
		local todo_uid = path[1]
		if value == "null" then
			-- nil value means entry was deleted
			state.tasks:delete(todo_uid)
			return
		end
		local todo_ical = vim.fn.json_decode(value)
		assert(todo_ical ~= nil, "Invalid JSON while reading updated entry")

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
	end)
	lds.init_done(state.conn)

	-- read all current data
	lds.init_stored_entries(state.conn)
	lds.execute_all_stored_entries_for_path_prefix(state.conn, { "resources" })

	state.lines = {}
	for _, task in ipairs(state.tasks:to_list()) do
		local line = ic.to_md_line(task.vtodo)
		if line then table.insert(state.lines, line) end
	end

	-- initially fill the buffer with initial data:
	vim.api.nvim_buf_set_lines(0, 0, -1, false, state.lines)
	vim.api.nvim_buf_set_option(state.main_buf_nr, "modified", false)
end

---@param state decscribe.State
function M.write_buffer(state)
	local main_buf_nr = state.main_buf_nr

	if main_buf_nr == nil then return end
	assert(main_buf_nr ~= nil)

	local old_contents = state.lines
	local new_contents = vim.api.nvim_buf_get_lines(main_buf_nr, 0, -1, false)
	local hunks = vim.diff(
		table.concat(old_contents, "\n"),
		table.concat(new_contents, "\n"),
		{ result_type = "indices" }
	)
	assert(type(hunks) == "table", "Decscribe: unexpected diff output")
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
				table.insert(
					lines_to_affect,
					{ idx = idx, line = new_contents[idx] }
				)
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
				on_line_changed(state, idx, new_line)
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
			on_line_removed(state, idx)
		else
			on_line_added(state, idx, change.line)
		end
	end

	-- updating succeeded
	state.lines = new_contents
	vim.api.nvim_buf_set_option(main_buf_nr, "modified", false)
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
