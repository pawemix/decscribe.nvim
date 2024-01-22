local ic = require("decscribe.ical")

local ffi = nil
local lds = nil

local M = {}

---@enum SyncType
M.SyncType = {
	tasks = "tasks",
	-- ... TODO
}



---TODO: capture actual well-typed return
---
---@return boolean ok whether the directory is valid decsync dir
function M.check_decsync_info(decsync_dir)
	ffi = ffi or require("ffi")
	lds = lds or ffi.load("libdecsync")
	ffi.cdef([[
		static int decsync_so_check_decsync_info(const char* decsync_dir);
	]])
	return lds.decsync_so_check_decsync_info(decsync_dir) == 0
end

function M.get_app_id(app_name)
	ffi = ffi or require("ffi")
	lds = lds or ffi.load("libdecsync")
	ffi.cdef([[
		static void decsync_so_get_app_id(
			const char* app_name,
			char* app_id, int len
		);
	]])

	local app_id_len = 1024
	local app_id_ref = ffi.new("char[?]", app_id_len)

	lds.decsync_so_get_app_id(app_name, app_id_ref, app_id_len)

	return ffi.string(app_id_ref)
end

---@param decsync_dir string
---@param sync_type SyncType
---@return string[] collections
function M.list_collections(decsync_dir, sync_type)
	decsync_dir = decsync_dir or ""
	sync_type = sync_type or ""

	ffi = ffi or require("ffi")
	lds = lds or ffi.load("libdecsync")

	ffi.cdef([[
		static int decsync_so_list_collections(
			const char* decsync_dir,
			const char* sync_type,
			char collections[][256],
			int max_len
		);
	]])

	-- local collection_str_cap = 256
	local collections_cap = 32
	local collections_ref = ffi.new("char[?][256]", collections_cap)

	local collections_count = lds.decsync_so_list_collections(
		decsync_dir,
		sync_type,
		collections_ref,
		collections_cap
	)

	-- accumulate the collections from C array to Lua table
	local collections = {}
	for idx = 0, collections_count - 1 do
		local collection = ffi.string(collections_ref[idx])
		table.insert(collections, collection)
	end

	return collections
end

-- TODO: refactor sync_type and collection params into category = ("rss" |
-- (sync_type|collection)) for safety (make illegal states irrepresentable)
--
---@class Collection
---@field sync_type SyncType
---@field collection string
--
---@alias Category ("rss" | Collection)


---@param decsync_dir string
---@param sync_type SyncType
---@param collection string SHOULD be supplied for `sync_type`s supporting collections, i.e EVERYTHING EXCEPT `"rss"`
---@param app_id string asdf
---@param path string[]
---@param key string?
---@param value string?
function M.set_entry(
	decsync_dir,
	sync_type,
	collection,
	app_id,
	path,
	key,
	value
)
	ffi = ffi or require("ffi")
	lds = lds or ffi.load("libdecsync")

	ffi.cdef([[
		typedef void* Decsync;

		static int decsync_so_new(
			Decsync* decsync,
			const char* decsync_dir,
			const char* sync_type,
			const char* collection,
			const char* own_app_id
		);

		static void decsync_so_free(Decsync decsync);

		static void decsync_so_set_entry(
			Decsync decsync,
			const char** path,
			int len,
			const char* key,
			const char* value
		);
	]])

	key = key or "null"
	value = value or "null"
	-- NOTE: `key` and `value` HAVE TO be JSON-serialized strings (or JSON null)!
	-- NOTE: if `value` is `null`, then the entry is deleted
	assert(key == "null" or vim.startswith(key, '"') and vim.endswith(key, '"'))
	assert(
		value == "null" or vim.startswith(value, '"') and vim.endswith(value, '"')
	)

	local path_arr = ffi.new("const char*[?]", #path)
	for i = 1, #path do
		path_arr[i - 1] = path[i]
	end

	local decsync_arr = ffi.new("Decsync[1]")
	local ds_so_new_ret =
		lds.decsync_so_new(decsync_arr, decsync_dir, sync_type, collection, app_id)
	assert(ds_so_new_ret == 0, "decsync_so_new failed")
	lds.decsync_so_set_entry(decsync_arr[0], path_arr, #path, key or "", value)
	lds.decsync_so_free(decsync_arr[0])
end

---@param decsync_dir string
---@param app_id string
---@param todo Todo
---@return any optional_error
function M.update_todo(decsync_dir, app_id, todo)
	local uid = todo.uid
	local ical = todo.ical
	local path = { "resources", uid }

	-- TODO: what if as a user I e.g. write into my description "STATUS:NEEDS-ACTION" string? will I inject metadata into the iCal?

	local status, _, status_i, status_j = find_ical_prop(ical, "STATUS")
	assert(status)
	local new_status = todo.completed and "COMPLETED" or "NEEDS-ACTION"
	ical = ical:sub(1, status_i - 1) .. new_status .. ical:sub(status_j + 1)

	local summary, _, summary_i, summary_j = find_ical_prop(ical, "SUMMARY")
	assert(summary)
	local new_summary = todo.summary
	ical = ical:sub(1, summary_i - 1) .. new_summary .. ical:sub(summary_j + 1)

	local ical_json = vim.fn.json_encode(ical)

	M.set_entry(decsync_dir, "tasks", todo.collection, app_id, path, nil, ical_json)
end

return M
