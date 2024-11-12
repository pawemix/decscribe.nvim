local lds = require("decscribe.libdecsync")
local app = require("decscribe.app")
local cr = require("decscribe.core")
local ic = require("decscribe.ical")

local M = {}

-- Type Definitions
-------------------

---@alias CompleteCustomListFunc
---| fun(arg_lead: string, cmd_line: string, cursor_pos: integer): string[]

-- Constants
------------

local APP_NAME = "decscribe"

local BUF_NOT_LOADED_MSG = "Decscribe buffer has not been loaded yet!"
	.. "\nLoad it with `:Decscribe DS-DIR COLL-NAME` first."

-- Global State
---------------

---@type string?
local ctx_decsync_dir = nil
---@type string?
local ctx_curr_coll_id = nil
---@type integer?
local ctx_buf_nr = nil
---@type decscribe.core.TodoStore?
local ctx_curr_store = nil
---@type Connection?
local ctx_lds_conn = nil
---@type string?
local ctx_tzid = nil

-- Helper Functions
-------------------

local function init_conn(decsync_dir, coll_id)
	return lds.connect(decsync_dir, "tasks", coll_id, lds.get_app_id(APP_NAME))
end

---checks the filesystem whether |path| is a decsync directory
---@param path string
---@return boolean
local function is_decsync_dir(path)
	return vim.fn.filereadable(vim.fn.expand(path .. "/.decsync-info")) == 1
end

---@param ds_dir string path to the decsync directory
---@return decscribe.Collections
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

---@param lds_conn Connection
---@return { [decscribe.ical.Uid]: decscribe.ical.String } uid_to_ical
local function lds_retrieve_icals(lds_conn)
	local uid_to_ical = {}
	lds.add_listener(lds_conn, { "resources" }, function(path, _, _, value)
		assert(#path == 1, "Unexpected path length while reading updated entry")
		---@type decscribe.ical.Uid
		---@diagnostic disable-next-line: assign-type-mismatch
		local todo_uid = path[1]
		if value == "null" then
			-- nil value means entry was deleted
			uid_to_ical[todo_uid] = nil
			return
		end
		local todo_ical = vim.fn.json_decode(value)
		assert(todo_ical ~= nil, "Invalid JSON while reading updated entry")
		uid_to_ical[todo_uid] = todo_ical
	end)
	lds.init_done(lds_conn)

	-- read all current data
	lds.init_stored_entries(lds_conn)
	lds.execute_all_stored_entries_for_path_prefix(lds_conn, { "resources" })

	return uid_to_ical
end

---@param lds_conn Connection
---@param uid decscribe.ical.Uid
---@param ical decscribe.ical.String
local function lds_update_ical(lds_conn, uid, ical)
	local ical_json = vim.fn.json_encode(ical)
	lds.set_entry(lds_conn, { "resources", uid }, nil, ical_json)
end

---@param lds_conn Connection
---@param uid decscribe.ical.Uid
local function lds_delete_ical(lds_conn, uid)
	lds.set_entry(lds_conn, { "resources", uid }, nil, nil)
end

---@param decsync_dir string
---@return number bufnr
local function create_decscribe_buffer(decsync_dir)
	local bufnr = vim.api.nvim_create_buf(true, false)
	--
	vim.api.nvim_buf_set_name(bufnr, "decscribe://" .. decsync_dir)
	vim.api.nvim_buf_set_option(bufnr, "filetype", "decscribe")
	vim.api.nvim_buf_set_option(bufnr, "buftype", "acwrite")
	--
	return bufnr
end

-- Plugin Setup
---------------

---@class (exact) decscribe.SetupOptions
---@field tzid? string timezone info, as per ICalendar TZID property

---@param opts? decscribe.SetupOptions
function M.setup(opts)
	opts = opts or {}
	ctx_tzid = opts.tzid or "America/Chicago"

	-- set up autocmds for reading/writing the buffer:
	local augroup = vim.api.nvim_create_augroup("Decscribe", { clear = true })

	vim.api.nvim_create_autocmd("BufReadCmd", {
		group = augroup,
		pattern = { "decscribe://*" },
		callback = function()
			if not ctx_lds_conn or not ctx_buf_nr then
				vim.notify(BUF_NOT_LOADED_MSG, vim.log.levels.ERROR)
				return
			end
			--
			local next_lines, next_store =
				app.read_icals(lds_retrieve_icals(ctx_lds_conn))
			--
			ctx_curr_store = next_store
			--
			vim.api.nvim_buf_set_lines(ctx_buf_nr, 0, -1, true, next_lines)
			vim.api.nvim_buf_set_option(ctx_buf_nr, "modified", false)
			-- Use 2-spaced tabs, so that:
			-- * indented blocks align nicely; and
			-- * line parsing is simple (no need to interpret amount of spaces).
			vim.api.nvim_buf_set_option(ctx_buf_nr, "expandtab", false)
			vim.api.nvim_buf_set_option(ctx_buf_nr, "tabstop", 2)
			vim.api.nvim_buf_set_option(ctx_buf_nr, "shiftwidth", 2)
		end,
	})

	vim.api.nvim_create_autocmd("BufWriteCmd", {
		group = augroup,
		pattern = { "decscribe://*" },
		callback = function()
			if not ctx_buf_nr or not ctx_lds_conn or not ctx_curr_store then
				vim.notify(BUF_NOT_LOADED_MSG, vim.log.levels.ERROR)
				return
			end
			-- gather input data:
			local next_lines = vim.api.nvim_buf_get_lines(ctx_buf_nr, 0, -1, true)
			-- sync the application state according to new buffer contents:
			local db_changes, on_db_changed =
				cr.sync_buffer(ctx_curr_store, next_lines)
			---@type decscribe.core.DbResult
			local db_result = {}
			-- update the buffer:
			for uid_or_pos, todo in pairs(db_changes) do
				if type(uid_or_pos) == "number" then
					-- new todo added
					local pos = uid_or_pos
					local curr_uids = {}
					for _, st in ipairs(ctx_curr_store) do
						curr_uids[#curr_uids + 1] = st.uid
					end
					local new_uid = ic.generate_uid(curr_uids)
					local ical_str = ic.tree2str(ic.todo2tree(todo), ic.default_key_comp)
					lds_update_ical(ctx_lds_conn, new_uid, ical_str)
					db_result[pos] = new_uid
				elseif type(uid_or_pos) == "string" then
					-- todo modified or deleted
					local uid = uid_or_pos
					if not todo then
						-- todo deleted
						lds_delete_ical(ctx_lds_conn, uid)
					else
						-- todo modified
						-- local prev_todo = ctx_curr_store[uid]
						local ical_str =
							error("FIXME: merge todo diff with curr todo? map to ical string")
						lds_update_ical(ctx_lds_conn, uid, ical_str)
					end
				else
					error("Unexpected type of uid_or_pos: " .. vim.inspect(uid_or_pos))
				end
			end

			ctx_curr_store = on_db_changed(db_result)
			vim.api.nvim_buf_set_option(ctx_buf_nr, "modified", false)
		end,
	})

	vim.api.nvim_create_user_command("Decscribe", function(params)
		local decsync_dir = params.fargs[1]
		if not decsync_dir then
			vim.notify_once(
				"Decsync directory (arg #1) has to be given",
				vim.log.levels.ERROR
			)
			return
		end
		-- expand potential path shortcuts like '~':
		decsync_dir = vim.fn.expand(decsync_dir)
		--
		local coll_name = params.fargs[2]
		if not coll_name then
			vim.notify_once(
				"Collection name (arg #2) has to be given",
				vim.log.levels.ERROR
			)
			return
		end
		local colls = list_collections(decsync_dir)
		local coll_id = colls[coll_name]
		if not coll_id then
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
		-- write new values into global state:
		ctx_decsync_dir = decsync_dir
		ctx_curr_coll_id = coll_id

		ctx_buf_nr = ctx_buf_nr or create_decscribe_buffer(ctx_decsync_dir)
		ctx_lds_conn = init_conn(ctx_decsync_dir, ctx_curr_coll_id)

		vim.api.nvim_set_current_buf(ctx_buf_nr)

		local lines, store = app.read_icals(lds_retrieve_icals(ctx_lds_conn))
		error("TODO: sort markdown lines")
		error("FIXME: ICal treats empty string as a category")

		ctx_curr_store = store

		vim.api.nvim_buf_set_lines(ctx_buf_nr, 0, -1, false, lines)
		vim.api.nvim_buf_set_option(ctx_buf_nr, "modified", false)
	end, {
		nargs = "+",
		---@type CompleteCustomListFunc
		complete = function(arg_lead, cmd_line)
			return app.complete_commandline(arg_lead, cmd_line, {
				is_decsync_dir_fn = is_decsync_dir,
				list_collections_fn = list_collections,
				complete_path_fn = function(path_prefix)
					return vim.fn.getcompletion(path_prefix, "file", true)
				end,
			})
		end,
	})
end

return M
