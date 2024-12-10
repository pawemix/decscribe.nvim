local M = {}

---@param shell_code string
---@vararg string
---@return string[]? output_lines
local function run(shell_code, ...)
	local args = { ... }
	for idx, arg in ipairs(args) do
		args[idx] = "'" .. arg:gsub("'", "'\\''") .. "'"
	end
	shell_code = "'" .. shell_code:gsub("'", "'\\''") .. "'"
	table.insert(args, 1, "sh")
	table.insert(args, 1, "")
	local prog = io.popen("sh -c " .. shell_code .. table.concat(args, " "), "r")
	if not prog then return nil end
	local lines = {}
	for line in prog:lines() do
		lines[#lines + 1] = line
	end
	prog:close()
	return lines
end

---Check the filesystem whether `path` is a decsync directory.
---@param path string
---@return boolean
function M.is_decsync_dir(path)
	path = path:gsub("/*$", "", 1)
	local ds_info_file, open_err = io.open(path .. "/.decsync-info", "r")
	if not ds_info_file or open_err then return false end
	ds_info_file:close()
	return true
end

---Get hostname using POSIX C function `gethostname`.
---@return string?
local function get_hostname()
	local ffi = require("ffi")
	ffi.cdef("int gethostname(char *name, size_t len)")
	local hostname_buf = ffi.new("char[?]", 256)
	local ret = ffi.C.gethostname(hostname_buf, 256)
	if ret ~= 0 then return nil end
	local hostname_str = ffi.string(hostname_buf)
	if type(hostname_str) ~= "string" then return nil end
	return ({ hostname_str:gsub("%z+$", "") })[1]
end

function M.get_app_id(app_name) return get_hostname() .. "-" .. app_name end

---@see get_app_id
---@param ds_dir string Path to a potential decsync directory.
---@return { [string]: string }? colls mapping of collection labels to UIDs
function M.list_task_colls(ds_dir)
	ds_dir = ds_dir:gsub("/*$", "", 1)
	if not M.is_decsync_dir(ds_dir) then return nil end
	-- TODO: use app_name and clone app dir from another, most recent app
	local task_metas = run('grep -F "name" "$1"/tasks/*/v2/*/info', ds_dir)
	if not task_metas then return nil end
	local out = {}
	for _, task_meta in pairs(task_metas) do
		local task_meta_cmps = vim.split(task_meta, ":")
		local coll_path = table.remove(task_meta_cmps, 1)
		local coll_info = vim.json.decode(table.concat(task_meta_cmps, ":"))
		local coll_label = coll_info[#coll_info]
		local coll_path_cmps = vim.split(coll_path, "/")
		local coll_id = coll_path_cmps[#coll_path_cmps - 3]
		out[coll_label] = coll_id
	end
	return out
end

---@param ds_dir string
---@param app_id string
---@param coll_id string
---@return { [string]: string }? uids_to_icals
function M.retrieve_task_icals(ds_dir, app_id, coll_id)
	ds_dir = ds_dir:gsub("/*$", "", 1)
	local bucket_jsons =
		run('cat "$1"/tasks/"$2"/v2/"$3"/??', ds_dir, coll_id, app_id)
	if not bucket_jsons then return nil end
	local uids_to_icals = {}
	local buckets = vim.json.decode(
		"[" .. table.concat(bucket_jsons, ",") .. "]",
		{ luanil = { object = true, array = true } }
	)
	for _, bucket in ipairs(buckets) do
		local uid = bucket[1][2]
		local ical = bucket[4]
		if ical then uids_to_icals[uid] = ical end
	end
	return uids_to_icals
end

---@alias decscribe.decsync.Uid string

---@param ds_dir string
---@param app_id string
---@param coll_id string
---@param ical_updates { [decscribe.decsync.Uid]: string|false }
---@return boolean success
function M.update_task_ical(ds_dir, app_id, coll_id, ical_updates)
	--- TODO rebuild into many ical updates/creations/removals at once
	local bucket_paths =
		run('ls -1d "$1"/tasks/"$2"/v2/"$3"/??', ds_dir, coll_id, app_id)
	for _, bucket_path in ipairs(bucket_paths) do

	end
end

return M
