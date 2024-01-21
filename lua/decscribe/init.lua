local M = {}

local PLUGIN_ROOT = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h:h:h")

---@type integer?
local main_buf_nr = nil
---@type table[]
local todos = {}
---@type string[]
local lines = {}

local function repopulate_buffer()
	if main_buf_nr == nil then return end
	assert(main_buf_nr ~= nil)

	-- obtain initial data using `decscribe` utility
	local tempfile = vim.fn.tempname()
	vim.fn.systemlist({ PLUGIN_ROOT .. "/decscribe", tempfile })
	local todos_json = vim.fn.readfile(tempfile)
	os.remove(tempfile)

	---@diagnostic disable-next-line: cast-local-type
	todos = vim.fn.json_decode(todos_json)
	assert(
		type(todos) == "table",
		"Decscribe: unexpected output from the decscribe utility"
	)
	table.sort(
		todos,
		function(a, b) return (a.completed and 1 or 0) < (b.completed and 1 or 0) end
	)

	lines = {}
	for _, todo in ipairs(todos) do
		local line = ""
		if todo.summary then
			line = "- [" .. (todo.completed and "x" or " ") .. "]"
			line = line .. " " .. todo.summary
		end
		if line then table.insert(lines, line) end
	end

	-- initially fill the buffer with initial data:
	vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(main_buf_nr, "modified", false)
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
			for _, hunk in ipairs(hunks) do
				local old_start, old_count, new_start, new_count = unpack(hunk)

				-- TODO: explore extmarks - maybe a powerful feature to track changes?

				-- TODO: handle other, more complex hunks than just one line change
				assert(
					old_count == 1 and new_count == 1,
					"decscribe: cannot handle hunks bigger than one line yet"
				)
				-- TODO: what if line changed?
				assert(old_start == new_start, "decscribe: cannot handle moving lines")

				local old_line = old_contents[old_start]
				local new_line = new_contents[new_start]
				local changed_todo = todos[old_start]
				local has_changed = false

				if -- todo status got swapped
					false
					or (old_line:match("[-*] [[] []]") and new_line:match("[-*] [[]x[]]"))
					or (old_line:match("[-*] [[]x[]]") and new_line:match("[-*] [[] []]"))
				then
					changed_todo.completed = not changed_todo.completed
					has_changed = true
				end

				-- TODO: summary changed
				local old_line_summary = old_line:gsub("[-*] +[[][ x][]] +", "", 1)
				local new_line_summary = new_line:gsub("[-*] +[[][ x][]] +", "", 1)

				if old_line_summary ~= new_line_summary then
					changed_todo.summary = new_line_summary
					has_changed = true
				end

				if not has_changed then goto continue end

				-- execute `decscribe` utility and send changed todo to it
				vim.fn.systemlist(
					{ PLUGIN_ROOT .. "/decscribe" },
					{ vim.fn.json_encode(changed_todo) }
				)
				if vim.v.shell_error ~= 0 then
					error("decscribe.py failed when updating the todos")
				else
					-- updating succeeded
					vim.api.nvim_buf_set_option(main_buf_nr, "modified", false)
					repopulate_buffer()
				end
				::continue::
			end
		end,
	})

	vim.api.nvim_create_user_command("Decscribe", function()
		-- FIXME: when rerunning the command and the buffer exists, don't create new
		-- buffer

		-- local decsync_dir_path = opts.args[1]

		-- initialize and configure the buffer
		if main_buf_nr == nil then
			main_buf_nr = vim.api.nvim_create_buf(true, false)

			-- XXX: hardcoded decsync dir
			local decsync_dir = vim.env.HOME .. "/some-ds-dir"

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
	end, {})
end

--[[
local ffi = require("ffi")
local lds = ffi.load("libdecsync")
-- important to NOT use inline C functions!
ffi.cdef("int decsync_so_check_decsync_info(const char* decsync_dir)")

local buf = ffi.new("const char[25]", decsync_dir)
print(lds.decsync_so_check_decsync_info(buf))
print(lds.decsync_so_check_decsync_info(decsync_dir))

]]

return M