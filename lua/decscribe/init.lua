local app = require("decscribe.app")
local ds = require("decscribe.decsync")

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
	tasks = {},
	lines = {},
	curr_coll_id = nil,
	decsync_dir = nil,
}

-- Functions
------------

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

---@return { [string]: string }?
local function try_retrieve_task_icals()
	local icals, err =
		ds.retrieve_task_icals(state.decsync_dir, state.curr_coll_id)
	if not icals then
		if not err then error("Unexpected error occurred!") end
		if err.no_ds_dir then
			local ds_dir = err.no_ds_dir
			vim.notify(
				("No Decsync directory at '%s'!"):format(ds_dir),
				vim.log.levels.ERROR
			)
			local should_create_dir = vim.fn
				.input({
					prompt = "Not a Decsync directory. Create one? [y/N] ",
					default = "n",
					cancelreturn = "n",
				})
				:lower() == "y"
			if should_create_dir then
				error("TODO create ds dir")
			else
				return nil
			end
		end
		if err.no_coll_dir then
			---@type string
			local ds_dir = err.no_coll_dir.ds_dir
			---@type string
			local coll_id = err.no_coll_dir.coll_id
			vim.notify(
				("No collection with ID '%s' at Decsync directory '%s'!"):format(
					coll_id,
					ds_dir
				),
				vim.log.levels.ERROR
			)
			local should_create_coll = vim.fn
				.input({
					prompt = "No such collection found. Create one? [y/N] ",
					default = "n",
					cancelreturn = "n",
				})
				:lower() == "y"
			if should_create_coll then error("TODO create coll") end
		end
		error("Unexpected error occurred!")
	end
	return icals
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
			local icals = assert(try_retrieve_task_icals())
			local new_lines = app.read_buffer(state, { icals = icals })
			nvim_buf_set_lines(0, -1, new_lines)
			nvim_buf_set_opt("modified", false)
		end,
	})

	vim.api.nvim_create_autocmd("BufWriteCmd", {
		group = augroup,
		pattern = { "decscribe://*" },
		callback = function()
			local ical_updates = app.write_buffer(state, {
				new_lines = nvim_buf_get_lines(0, -1),
			})
			ds.patch_task_icals(
				assert(state.decsync_dir),
				assert(ds.get_app_id(APP_NAME)),
				assert(state.curr_coll_id),
				ical_updates.changes
			)
			nvim_buf_set_opt("modified", false)
		end,
	})

	vim.api.nvim_create_user_command("Decscribe", function(params)
		app.open_buffer(state, {
			decsync_dir = params.fargs[1],
			collection_label = params.fargs[2],
			list_collections_fn = function(ds_dir)
				return assert(ds.list_task_colls(ds_dir))
			end,
			read_buffer_params = {
				db_retrieve_icals = function()
					error("app.open_buffer shouldn't need db_retrieve_icals now!")
				end,
				ui = {
					buf_set_lines = nvim_buf_set_lines,
					buf_get_lines = nvim_buf_get_lines,
					buf_set_opt = nvim_buf_set_opt,
				},
			},
		})
		local new_icals = assert(try_retrieve_task_icals())
		local new_lines = app.read_buffer(state, { icals = new_icals })
		nvim_buf_set_lines(0, -1, new_lines)
		nvim_buf_set_opt("modified", false)
	end, {
		nargs = "+",
		---@type CompleteCustomListFunc
		complete = function(arg_lead, cmd_line)
			return app.complete_commandline(arg_lead, cmd_line, {
				is_decsync_dir_fn = ds.is_decsync_dir,
				list_collections_fn = function(ds_dir)
					local colls, err = ds.list_task_colls(ds_dir)
					if colls then
						if err then vim.notify(vim.inspect(err), vim.log.levels.WARN) end
						return colls
					elseif err and err.no_ds_dir then
						vim.notify_once(
							("No Decsync directory at '%s'."):format(err.no_ds_dir),
							vim.log.levels.WARN
						)
					elseif err and err.no_coll_dir then
						vim.notify_once(
							("No collection named '%s' at Decsync directory '%s'."):format(
								err.no_coll_dir.coll_id,
								err.no_coll_dir.ds_dir
							),
							vim.log.levels.WARN
						)
					else
						vim.notify_once(
							"Unexpected error while listing collections.",
							vim.log.levels.WARN
						)
					end
					return {}
				end,
				complete_path_fn = function(path_prefix)
					return vim.fn.getcompletion(path_prefix, "file", true)
				end,
			})
		end,
	})
end

return M
