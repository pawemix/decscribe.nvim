local lds = require("decscribe.libdecsync")
local ic = require("decscribe.ical")

local M = {}

-- Type Definitions
-------------------

---@alias CompleteCustomListFunc
---| fun(arg_lead: string, cmd_line: string, cursor_pos: integer): string[]

---@class Todo
---@field uid ical.uid_t
---@field collection string
---@field vtodo ical.vtodo_t
---@field ical ical.ical_t
local Todo = {}

-- Constants
------------

local APP_NAME = "decscribe"

-- Global State
---------------

---@type Connection
local conn = nil
---@type integer?
local main_buf_nr = nil
---@type table<ical.uid_t, Todo>
local todos = {}
---@type table<number, ical.uid_t>
local idx_to_uids = {}
---@type string[]
local lines = {}
---@type string
local curr_coll_id = nil
---@type string?
local decsync_dir = nil

-- Functions
------------

---@alias coll_name_t string
---@alias coll_id_t string
---@alias colls_t table<coll_name_t, coll_id_t>

---checks the filesystem whether |path| is a decsync directory
---@param path string
---@return boolean
local function is_decsync_dir(path)
	return vim.fn.filereadable(vim.fn.expand(path .. "/.decsync-info")) == 1
end

---@param ds_dir string path to the decsync directory
---@return colls_t
local function list_collections(ds_dir)
	local app_id = lds.get_app_id(APP_NAME)

	local coll_ids = lds.list_collections(ds_dir, "tasks")
	local coll_name_to_ids = {}

	for _, coll_id in ipairs(coll_ids) do
		local coll_conn
		coll_conn = lds.connect(ds_dir, "tasks", coll_id, app_id)
		lds.add_listener(coll_conn, { "info" }, function(_, _, key, value)
			key = key or "null"
			key = vim.fn.json_decode(key)
			value = value or "null"
			value = vim.fn.json_decode(value)
			if key == "name" and value then coll_name_to_ids[value] = coll_id end
		end)
		lds.init_done(coll_conn)
		lds.init_stored_entries(coll_conn)
		lds.execute_all_stored_entries_for_path_exact(coll_conn, { "info" })
	end

	return coll_name_to_ids
end

local function repopulate_buffer()
	if main_buf_nr == nil then return end
	assert(main_buf_nr ~= nil)
	assert(curr_coll_id)
	assert(decsync_dir)

	conn =
		lds.connect(decsync_dir, "tasks", curr_coll_id, lds.get_app_id(APP_NAME))

	lds.add_listener(conn, { "resources" }, function(path, _, _, value)
		assert(#path == 1, "Unexpected path length while reading updated entry")
		---@type ical.uid_t
		---@diagnostic disable-next-line: assign-type-mismatch
		local todo_uid = path[1]
		if value == "null" then
			-- nil value means entry was deleted
			todos[todo_uid] = nil
			return
		end
		local todo_ical = vim.fn.json_decode(value)
		assert(todo_ical ~= nil, "Invalid JSON while reading updated entry")

		local categories = vim.split(
			ic.find_ical_prop(todo_ical, "CATEGORIES") or "",
			",",
			{ trimempty = true }
		)
		-- NOTE: there is a convention (or at least tasks.org follows it) to sort
		-- categories alphabetically:
		table.sort(categories)

		local priority = ic.priority_t.undefined
		local priority_str = ic.find_ical_prop(todo_ical, "PRIORITY")
		if priority_str and tonumber(priority_str) then
			priority = tonumber(priority_str) or ic.priority_t.undefined
		end

		---@type ical.vtodo_t
		local vtodo = {
			completed = ic.find_ical_prop(todo_ical, "STATUS") == "COMPLETED",
			priority = priority,
			summary = ic.find_ical_prop(todo_ical, "SUMMARY") or "",
			categories = categories,
			description = ic.find_ical_prop(todo_ical, "DESCRIPTION") or "",
		}

		---@type Todo
		local todo = {
			vtodo = vtodo,
			ical = todo_ical,
			uid = todo_uid,
			collection = curr_coll_id,
		}

		todos[todo_uid] = todo
	end)
	lds.init_done(conn)

	-- read all current data
	lds.init_stored_entries(conn)
	lds.execute_all_stored_entries_for_path_prefix(conn, { "resources" })

	idx_to_uids = {}
	for uid, _ in pairs(todos) do
		table.insert(idx_to_uids, uid)
	end

	table.sort(idx_to_uids, function(uid1, uid2)
		local completed1 = todos[uid1].vtodo.completed and 1 or 0
		local completed2 = todos[uid2].vtodo.completed and 1 or 0
		if completed1 ~= completed2 then return completed1 < completed2 end

		local priority1 = tonumber(todos[uid1].vtodo.priority) or 0
		local priority2 = tonumber(todos[uid2].vtodo.priority) or 0
		if priority1 ~= priority2 then return priority1 < priority2 end

		local summary1 = todos[uid1].vtodo.summary
		local summary2 = todos[uid2].vtodo.summary
		return summary1 < summary2
	end)

	lines = {}
	for _, uid in ipairs(idx_to_uids) do
		local todo = todos[uid]
		local line = ic.to_md_line(todo.vtodo)
		if line then table.insert(lines, line) end
	end

	-- initially fill the buffer with initial data:
	vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(main_buf_nr, "modified", false)
end

--- XXX: Indices in `todos` will change - any data referring to those indices
--- may break unless properly handled.
local function on_line_removed(idx)
	local uid = idx_to_uids[idx]
	table.remove(idx_to_uids, idx)
	todos[uid] = nil
	---@diagnostic disable-next-line: assign-type-mismatch
	lds.set_entry(conn, { "resources", uid }, nil, nil)
end

--- XXX: Indices in `todos` will change - any data referring to those indices
--- may break unless properly handled.
local function on_line_added(idx, line)
	local uid = ic.generate_uid(vim.tbl_keys(todos))
	local vtodo = ic.parse_md_line(line)
	-- TODO: add a diagnostic to the line
	assert(vtodo, "Invalid line while adding new entry")
	local ical = ic.create_ical_vtodo(uid, vtodo)
	---@type Todo
	local todo = {
		uid = uid,
		collection = curr_coll_id,
		vtodo = vtodo,
		ical = ical,
	}
	todos[uid] = todo
	table.insert(idx_to_uids, idx, uid)
	local ical_json = vim.fn.json_encode(ical)
	---@diagnostic disable-next-line: assign-type-mismatch, param-type-mismatch
	lds.set_entry(conn, { "resources", uid }, nil, ical_json)
end

local function on_line_changed(idx, old_line, new_line)
	local changed_todo = todos[idx_to_uids[idx]]
	local has_changed = false

	local old_vtodo = ic.parse_md_line(old_line)
	local new_vtodo = ic.parse_md_line(new_line)

	assert(old_vtodo)
	assert(new_vtodo)

	if old_vtodo.completed ~= new_vtodo.completed then
		changed_todo.vtodo.completed = new_vtodo.completed
		has_changed = true
	end
	if old_vtodo.summary ~= new_vtodo.summary then
		changed_todo.vtodo.summary = new_vtodo.summary
		has_changed = true
	end
	if old_vtodo.description ~= new_vtodo.description then
		changed_todo.vtodo.description = new_vtodo.description
		has_changed = true
	end
	if not vim.deep_equal(old_vtodo.categories, new_vtodo.categories) then
		changed_todo.vtodo.categories = new_vtodo.categories
		has_changed = true
	end
	if old_vtodo.priority ~= new_vtodo.priority then
		changed_todo.vtodo.priority = new_vtodo.priority
		has_changed = true
	end

	if has_changed then lds.update_todo(conn, changed_todo) end
end

function M.setup()
	-- set up autocmds for reading/writing the buffer:
	local augroup = vim.api.nvim_create_augroup("Decscribe", { clear = true })

	vim.api.nvim_create_autocmd("BufReadCmd", {
		group = augroup,
		pattern = { "decscribe://*" },
		callback = function() repopulate_buffer() end,
	})

	vim.api.nvim_create_autocmd("BufWriteCmd", {
		group = augroup,
		pattern = { "decscribe://*" },
		callback = function()
			if main_buf_nr == nil then return end
			assert(main_buf_nr ~= nil)

			local old_contents = lines
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
						local old_line = old_contents[idx]
						local new_line = new_contents[idx]
						on_line_changed(idx, old_line, new_line)
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
					on_line_removed(idx)
				else
					on_line_added(idx, change.line)
				end
			end

			-- updating succeeded
			lines = new_contents
			vim.api.nvim_buf_set_option(main_buf_nr, "modified", false)
		end,
	})

	vim.api.nvim_create_user_command("Decscribe", function(params)
		decsync_dir = params.fargs[1]
		if not decsync_dir then
			vim.notify_once(
				"Decsync directory (arg #1) has to be given",
				vim.log.levels.ERROR
			)
			return
		end
		-- expand potential path shortcuts like '~':
		decsync_dir = vim.fn.expand(decsync_dir)

		local coll_name = params.fargs[2]
		if not coll_name then
			vim.notify_once(
				"Collection name (arg #2) has to be given",
				vim.log.levels.ERROR
			)
			return
		end
		local colls = list_collections(decsync_dir)
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
		curr_coll_id = colls[coll_name]

		-- FIXME: when rerunning the command and the buffer exists, don't create new
		-- buffer

		-- initialize and configure the buffer
		if main_buf_nr == nil then
			main_buf_nr = vim.api.nvim_create_buf(true, false)

			vim.api.nvim_buf_set_name(main_buf_nr, "decscribe://" .. decsync_dir)
			vim.api.nvim_buf_set_option(main_buf_nr, "filetype", "decscribe")
			vim.api.nvim_buf_set_option(main_buf_nr, "buftype", "acwrite")
			-- vim.api.nvim_buf_set_option(bufnr, "number", false)
			-- vim.api.nvim_buf_set_option(bufnr, "cursorline", false)
			-- vim.cmd [[setlocal omnifunc=v:lua.octo_omnifunc]]
			-- vim.cmd [[setlocal conceallevel=2]]
			-- vim.cmd [[setlocal signcolumn=yes]]

			-- TODO: apply buf-local mappings (e.g. <C-Space> on checking todos)
		end

		if vim.api.nvim_get_current_buf() ~= main_buf_nr then
			vim.api.nvim_set_current_buf(main_buf_nr)
		end

		repopulate_buffer()
	end, {
		nargs = "+",
		---@type CompleteCustomListFunc
		complete = function(arg_lead, cmd_line)
			local cmd_line_comps = vim.split(cmd_line, "%s+")
			-- if this is the 1st argument (besides the cmd), provide path completion:
			if arg_lead == cmd_line_comps[2] then
				return vim.fn.getcompletion(arg_lead, "file", true)
			end
			-- otherwise, this is the second argument:
			local ds_dir = vim.fn.expand(cmd_line_comps[2])
			if not is_decsync_dir(ds_dir) then return {} end

			local coll_names = vim.tbl_keys(list_collections(ds_dir))
			return vim.tbl_filter(
				function(s) return vim.startswith(s, arg_lead) end,
				coll_names
			)
		end,
	})
end

return M
