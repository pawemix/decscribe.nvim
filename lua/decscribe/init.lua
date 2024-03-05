local lds = require("decscribe.libdecsync")
local ts = require("decscribe.tasks")
local app = require("decscribe.app")

local M = {}

-- Type Definitions
-------------------

---@alias CompleteCustomListFunc
---| fun(arg_lead: string, cmd_line: string, cursor_pos: integer): string[]

-- Constants
------------

local APP_NAME = "decscribe"

-- Global State
---------------

---@type decscribe.State
local state = {
	main_buf_nr = nil,
	tasks = ts.Tasks:new(),
	lines = {},
	curr_coll_id = nil,
	decsync_dir = nil,
}

---@type Connection
local conn = nil

-- Functions
------------

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

local function lds_retrieve_icals()
	conn =
		lds.connect(state.decsync_dir, "tasks", state.curr_coll_id, lds.get_app_id(APP_NAME))
	local uid_to_ical = {}
	lds.add_listener(conn, { "resources" }, function(path, _, _, value)
		assert(#path == 1, "Unexpected path length while reading updated entry")
		---@type ical.uid_t
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
	lds.init_done(conn)

	-- read all current data
	lds.init_stored_entries(conn)
	lds.execute_all_stored_entries_for_path_prefix(conn, { "resources" })

	return uid_to_ical
end

local function lds_update_ical(uid, ical)
	local ical_json = vim.fn.json_encode(ical)
	lds.set_entry(conn, { "resources", uid }, nil, ical_json)
end

local function lds_delete_ical(uid)
	lds.set_entry(conn, { "resources", uid }, nil, nil)
end

local function nvim_buf_set_opt(opt_name, value)
	vim.api.nvim_buf_set_option(state.main_buf_nr, opt_name, value)
end

local function nvim_buf_get_lines(start, end_)
	local bufnr = state.main_buf_nr
	assert(bufnr)
	return vim.api.nvim_buf_get_lines(bufnr, start, end_, true)
end
local function nvim_buf_set_lines(start, end_, lines)
	local bufnr = state.main_buf_nr
	assert(bufnr)
	vim.api.nvim_buf_set_lines(bufnr, start, end_, false, lines)
end

---@class (exact) decscribe.SetupOptions
---@field tzid? string timezone info, as per ICalendar TZID property

---@param opts? decscribe.SetupOptions
function M.setup(opts)
	opts = opts or {}
	state.tzid = opts.tzid or "America/Chicago"

	-- set up autocmds for reading/writing the buffer:
	local augroup = vim.api.nvim_create_augroup("Decscribe", { clear = true })

	vim.api.nvim_create_autocmd("BufReadCmd", {
		group = augroup,
		pattern = { "decscribe://*" },
		callback = function()
			app.read_buffer(state, {
				db_retrieve_icals = lds_retrieve_icals,
				ui = {
					buf_set_lines = nvim_buf_set_lines,
					buf_get_lines = nvim_buf_get_lines,
					buf_set_opt = nvim_buf_set_opt,
				},
			})
		end,
	})

	vim.api.nvim_create_autocmd("BufWriteCmd", {
		group = augroup,
		pattern = { "decscribe://*" },
		callback = function()
			app.write_buffer(state, {
				db_delete_ical = lds_delete_ical,
				db_update_ical = lds_update_ical,
				ui = {
					buf_set_lines = nvim_buf_set_lines,
					buf_get_lines = nvim_buf_get_lines,
					buf_set_opt = nvim_buf_set_opt,
				},
			})
		end,
	})

	vim.api.nvim_create_user_command("Decscribe", function(params)
		app.open_buffer(state, {
			decsync_dir = params.fargs[1],
			collection_label = params.fargs[2],
			list_collections_fn = list_collections,
			read_buffer_params = {
				db_retrieve_icals = lds_retrieve_icals,
				ui = {
					buf_set_lines = nvim_buf_set_lines,
					buf_get_lines = nvim_buf_get_lines,
					buf_set_opt = nvim_buf_set_opt,
				},
			}
		})
	end, {
		nargs = "+",
		---@type CompleteCustomListFunc
		complete = function(arg_lead, cmd_line)
			return app.complete_commandline(arg_lead, cmd_line, {
					is_decsync_dir_fn = is_decsync_dir,
					list_collections_fn = list_collections,
					complete_path_fn = function (path_prefix)
						return vim.fn.getcompletion(path_prefix, "file", true)
					end
				})
		end,
	})
end

return M
