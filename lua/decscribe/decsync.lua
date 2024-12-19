local os = require("os")

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

---@param shell_code string
---@vararg string
---@return fun(): string? next
local function run_iter(shell_code, ...)
	local args = { ... }
	for idx, arg in ipairs(args) do
		args[idx] = "'" .. arg:gsub("'", "'\\''") .. "'"
	end
	shell_code = "'" .. shell_code:gsub("'", "'\\''") .. "'"
	table.insert(args, 1, "sh")
	table.insert(args, 1, "")
	local prog = io.popen("sh -c " .. shell_code .. table.concat(args, " "), "r")
	if not prog then return function() return nil end end
	local lines_next = prog:lines()
	return function()
		local next = lines_next()
		if next then return next end
		prog:close()
		return nil
	end
end

---@param path string
---@return string
local function normalize_path(path)
	-- Cut trailing slash from the path if present:
	if string.sub(path, #path) == "/" then
		path = string.sub(path, 1, #path - 1)
	end
	return path
end

---Check the filesystem whether `path` is a decsync directory.
---@param path string
---@return boolean
function M.is_decsync_dir(path)
	path = normalize_path(path)
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

---@class (exact) decscribe.decsync.NoDsDir
---@field no_ds_dir string

---@param ds_dir string
---@return decscribe.decsync.NoDsDir
local function NoDsDir(ds_dir)
	---@type decscribe.decsync.NoDsDir
	return { no_ds_dir = ds_dir }
end

---@class (exact) decscribe.decsync.NoCollDirModel
---@field ds_dir string
---@field coll_id string

---@class (exact) decscribe.decsync.NoCollDir
---@field no_coll_dir decscribe.decsync.NoCollDirModel

---@param ds_dir string
---@param coll_id string
---@return decscribe.decsync.NoCollDir
local function NoCollDir(ds_dir, coll_id)
	---@type decscribe.decsync.NoCollDir
	return { no_coll_dir = { ds_dir = ds_dir, coll_id = coll_id } }
end

---@alias decscribe.decsync.DecsyncError
---| decscribe.decsync.NoDsDir
---| decscribe.decsync.NoCollDir
---| decscribe.decsync.NoAppDir

---@see get_app_id
---@param ds_dir string Path to a potential decsync directory.
---@return { [string]: string }? colls mapping of collection labels to UIDs
---@return (decscribe.decsync.NoDsDir | decscribe.decsync.NoCollDir)?
function M.list_task_colls(ds_dir)
	ds_dir = ds_dir:gsub("/*$", "", 1)
	if not M.is_decsync_dir(ds_dir) then return nil, NoDsDir(ds_dir) end
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
---@param coll_id string
---@return boolean
local function is_coll_dir(ds_dir, coll_id)
	ds_dir = normalize_path(ds_dir)
	return "" ~= vim.fn.glob(table.concat({ds_dir, "tasks", coll_id}, "/"))
end

---@param ds_dir string
---@param coll_id string
---@return { [string]: string }? uids_to_icals
---@return (decscribe.decsync.NoDsDir | decscribe.decsync.NoCollDir)?
function M.retrieve_task_icals(ds_dir, coll_id)
	-- Normalize input parameters:
	ds_dir = normalize_path(ds_dir)
	-- Ensure Decsync IO environment is present & correct:
	if not M.is_decsync_dir(ds_dir) then
		return nil, NoDsDir(ds_dir)
	end
	if not is_coll_dir(ds_dir, coll_id) then
		return nil, NoCollDir(ds_dir, coll_id)
	end
	-- Retrieve the ICals:
	local uid_to_updated_datetime = {}
	local uid_to_ical = {}
	for entry_str in run_iter('cat "$1"/tasks/"$2"/v2/*/??', ds_dir, coll_id) do
		local entry = assert(
			vim.json.decode(entry_str, { luanil = { object = true, array = true }}),
			"Could not JSON-parse an entry: " .. vim.inspect(entry_str)
		)
		local uid = assert(entry[1][2])
		local updated_datetime = assert(
			entry[2], "entry[2]: string expected; got " .. vim.inspect(entry[2]))
		local ical_or_nil = entry[4]
		assert(
			type(ical_or_nil) == "string" or type(ical_or_nil) == "nil",
			"Unexpected type of ical_or_nil: " .. type(ical_or_nil))
		-- Use current todo replica if
		-- it's not there yet or previously read replica was older:
		if
			not uid_to_updated_datetime[uid]
			or uid_to_updated_datetime[uid] < updated_datetime
		then
			uid_to_ical[uid] = ical_or_nil
			uid_to_updated_datetime[uid] = updated_datetime
		end
	end
	return uid_to_ical
end

---Get a bucket with the least amount of lines.
---@param t { [BucketPath]: integer }
---@return BucketPath?
local function get_by_least_count(t)
	local min_count = math.huge
	local min_bucket = nil
	for bucket_path, count in pairs(t) do
		if count < min_count then
			min_count = count
			min_bucket = bucket_path
		end
	end
	return min_bucket
end

local function is_app_dir(ds_dir, coll_id, app_id)
	ds_dir = normalize_path(ds_dir)
	local info_path =
		table.concat({ ds_dir, "tasks", coll_id, "v2", app_id, "info" }, "/")
	if true then return 1 == vim.fn.filereadable(info_path) end
	-- TODO check contents of the info file
end

function M.create_app_dir(ds_dir, coll_id, app_id)
	error("TODO: create_app_dir")
	error("TODO: %s/tasks/%s/local/%s/info: version: 2")
	error("TODO: %s/tasks/%s/local/%s/sequences: {[app_name]: {[bucket_name]: entries_count}}")
	error("TODO: copy name from other apps? (string)")
	error("TODO: copy color from other apps? (#aabbcc)")
	error("TODO: read supported-version of other apps? (2)")
	error("TODO: write last-active-<app-id> in other apps' info? (YYYY-MM-DD)")
end

---@class (exact) decscribe.decsync.NoAppDir
---@field noAppDir decscribe.decsync.NoAppDirModel

---@class (exact) decscribe.decsync.NoAppDirModel
---@field ds_dir string
---@field coll_id string
---@field app_id string

---@param ds_dir string
---@param coll_id string
---@param app_id string
---@return decscribe.decsync.NoAppDir
local function NoAppDir(ds_dir, coll_id, app_id)
	---@type decscribe.decsync.NoAppDir
	return {
		noAppDir = {
			ds_dir = ds_dir,
			coll_id = coll_id,
			app_id = app_id,
		}
	}
end

---@alias decscribe.decsync.Uid string

---@param ds_dir string
---@param app_id string
---@param coll_id string
---@param ical_updates { [decscribe.decsync.Uid]: string|false }
---@return boolean success
---@return decscribe.decsync.DecsyncError?
function M.patch_task_icals(ds_dir, app_id, coll_id, ical_updates)
	if not M.is_decsync_dir(ds_dir) then
		return false, NoDsDir(ds_dir)
	end
	if not is_coll_dir(ds_dir, coll_id) then
		return false, NoCollDir(ds_dir, coll_id)
	end
	if not is_app_dir(ds_dir, coll_id, app_id) then
		return false, NoAppDir(ds_dir, coll_id, app_id)
	end
	local bucket_paths =
		run('ls -1d "$1"/tasks/"$2"/v2/"$3"/??', ds_dir, coll_id, app_id)
	---@alias BucketPath string
	---@type { [BucketPath]: integer }
	local bucket_counts = {}
	assert(bucket_paths, "Couldn't read decsync task file entries!")
	for _, bucket_path in ipairs(bucket_paths) do
		local bucket_file_ro = io.open(bucket_path, "r")
		assert(bucket_file_ro, ("Couldn't open '%s'!"):format(bucket_path))
		local bucket_lines = {}
		for entry_line in bucket_file_ro:lines("*l") do
			bucket_lines[#bucket_lines + 1] = entry_line
		end
		bucket_file_ro:close()

		local bucket_changed = false
		for idx, entry_line in ipairs(bucket_lines) do
			local entry = assert(
				vim.json.decode(
					entry_line,
					{ luanil = { object = true, array = true } }
				)
			)
			local uid = entry[1][2]
			-- Don't update anything if no changes to the todo with this UID:
			if ical_updates[uid] == nil then goto continue_bucket_lines end
			-- Bump last update datetime (ISO8601 w/o TZ info in UTC Zero):
			entry[2] = os.date("!%Y-%m-%dT%H:%M:%S")
			-- Update the entry
			-- NOTE: vim.v.null has to be used instead of nil, otherwise JSON won't
			-- render the object key / array element at all if possible.
			entry[4] = ical_updates[uid] or vim.v.null
			bucket_lines[idx] = assert(vim.json.encode(entry))
			ical_updates[uid] = nil
			bucket_changed = true
			--
			::continue_bucket_lines::
		end -- for bucket_lines
		bucket_counts[bucket_path] = #bucket_lines
		-- Rewrite the bucket with new lines if anything changed:
		if bucket_changed then
			local bucket_file_wo = assert(
				io.open(bucket_path, "w"),
				("Couldn't open '%s' for writing!"):format(bucket_path)
			)
			bucket_file_wo:write(table.concat(bucket_lines, "\n") .. "\n")
			bucket_file_wo:close()
		end -- if bucket_changed
	end -- for bucket_paths

	-- Remaining ical updates are NEW entries - insert them:
	for uid, ical_or_false in pairs(ical_updates) do
		assert(
			type(ical_or_false) == "string" or ical_or_false == false,
			"Unexpected type of ical_or_false: " .. type(ical_or_false))
		local sel_bucket_path =
			assert(get_by_least_count(bucket_counts)) -- no buckets is unexpected
		local sel_bucket_file = assert(
			io.open(sel_bucket_path, "a"),
			("Couldn't open '%s' file for appending!"):format(sel_bucket_path)
		)
		local entry = {
			{ "resources", uid },
			os.date("!%Y-%m-%dT%H:%M:%S"),
			vim.v.NIL,
			ical_or_false or vim.v.NIL
		}
		local entry_json = assert(
			vim.json.encode(entry),
			"Entry could not be encoded as JSON: " .. vim.inspect(entry)
		)
		sel_bucket_file:write(entry_json .. "\n")
		assert(
			sel_bucket_file:close(),
			("Couldn't close file '%s'!"):format(sel_bucket_path)
		)
		bucket_counts[sel_bucket_path] = bucket_counts[sel_bucket_path] + 1
	end -- ical creations
	return true, nil
end

return M
