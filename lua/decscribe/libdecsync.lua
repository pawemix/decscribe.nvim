local ic = require("decscribe.ical")

local ffi = nil
local lds = nil

local M = {}

---@enum SyncType
M.SyncType = {
	tasks = "tasks",
	-- ... TODO
}

---@class (exact) libdecsync.json_string_t

---@alias Callback
---| fun(path: string[], datetime: string, key: string?, value: string?)

---@alias Connection ffi.cdata*

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

---@param decsync_dir string
---@param sync_type SyncType
---@param collection string
---@param app_id string
function M.connect(decsync_dir, sync_type, collection, app_id)
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
	]])

	local decsync_arr = ffi.new("Decsync[1]")
	-- FIXME: Apparently, this gc runs prematurely, and thus crashes the app very
	-- often due to a segfault, because a set_entry is called on an already-freed
	-- connection:
	--ffi.gc(decsync_arr[0], function() lds.decsync_so_free(decsync_arr[0]) end)
	local ds_so_new_ret =
		lds.decsync_so_new(decsync_arr, decsync_dir, sync_type, collection, app_id)
	assert(ds_so_new_ret == 0, "decsync_so_new failed")

	return decsync_arr
end

---@param connection Connection
---@param path string[]
---@param callback Callback
function M.add_listener(connection, path, callback)
	ffi = ffi or require("ffi")
	lds = lds or ffi.load("libdecsync")

	ffi.cdef([[
		static void decsync_so_add_listener(
			Decsync decsync,
			const char** subpath,
			int len,
			void (*on_entry_update)(
				const char** path,
				int len,
				const char* datetime,
				const char* key,
				const char* value,
				void* extra
			)
		);

		typedef void (*callback_t)(
			const char**,
			int,
			const char*,
			const char*,
			const char*,
			void*
		);
	]])

	local path_arr = ffi.new("const char*[?]", #path)
	for i = 1, #path do
		path_arr[i - 1] = path[i]
	end

	lds.decsync_so_add_listener(
		connection[0],
		path_arr,
		#path,
		function(path_, len, datetime, key, value)
			local path_table = {}
			for i = 1, len do
				path_table[i] = ffi.string(path_[i - 1])
			end
			callback(
				path_table,
				ffi.string(datetime),
				ffi.string(key),
				ffi.string(value)
			)
		end
	)
end

---@param connection Connection
function M.init_stored_entries(connection)
	ffi = ffi or require("ffi")
	lds = lds or ffi.load("libdecsync")

	ffi.cdef([[
		static void decsync_so_init_stored_entries(Decsync decsync);
	]])

	lds.decsync_so_init_stored_entries(connection[0])
end

---@param connection Connection
---@param path_exact string[]
function M.execute_all_stored_entries_for_path_exact(connection, path_exact)
	ffi = ffi or require("ffi")
	lds = lds or ffi.load("libdecsync")

	ffi.cdef([[
		static void decsync_so_execute_all_stored_entries_for_path_exact(
			Decsync decsync,
			const char** path,
			int len_path,
			void* extra
		);
	]])

	local path_exact_arr = ffi.new("const char*[?]", #path_exact)
	for i = 1, #path_exact do
		path_exact_arr[i - 1] = path_exact[i]
	end

	lds.decsync_so_execute_all_stored_entries_for_path_exact(
		connection[0],
		path_exact_arr,
		#path_exact,
		nil
	)
end

---@param connection Connection
---@param path_prefix string[]
function M.execute_all_stored_entries_for_path_prefix(connection, path_prefix)
	ffi = ffi or require("ffi")
	lds = lds or ffi.load("libdecsync")

	ffi.cdef([[
		static void decsync_so_execute_all_stored_entries_for_path_prefix(
			Decsync decsync,
			const char** path,
			int len_path,
			void* extra
		);
	]])

	local path_prefix_arr = ffi.new("const char*[?]", #path_prefix)
	for i = 1, #path_prefix do
		path_prefix_arr[i - 1] = path_prefix[i]
	end

	lds.decsync_so_execute_all_stored_entries_for_path_prefix(
		connection[0],
		path_prefix_arr,
		#path_prefix,
		nil
	)
end

---@param connection Connection
function M.init_done(connection)
	ffi = ffi or require("ffi")
	lds = lds or ffi.load("libdecsync")

	ffi.cdef([[
		static void decsync_so_init_done(Decsync decsync);
	]])

	lds.decsync_so_init_done(connection[0])
end

-- TODO: refactor sync_type and collection params into category = ("rss" |
-- (sync_type|collection)) for safety (make illegal states irrepresentable)
--
---@class Collection
---@field sync_type SyncType
---@field collection string
--
---@alias Category ("rss" | Collection)

---@param connection Connection
---@param path string[]
---@param key libdecsync.json_string_t?
---@param value libdecsync.json_string_t?
function M.set_entry(connection, path, key, value)
	ffi = ffi or require("ffi")
	lds = lds or ffi.load("libdecsync")

	ffi.cdef([[
		static void decsync_so_set_entry(
			Decsync decsync,
			const char** path,
			int len,
			const char* key,
			const char* value
		);
	]])

	---@diagnostic disable-next-line: cast-local-type
	key = key or "null"
	---@diagnostic disable-next-line: cast-local-type
	value = value or "null"
	-- NOTE: `key` and `value` HAVE TO be JSON-serialized strings (or JSON null)!
	-- NOTE: if `value` is `null`, then the entry is deleted
	---@diagnostic disable-next-line: param-type-mismatch
	assert(key == "null" or vim.startswith(key, '"') and vim.endswith(key, '"'))
	assert(
		---@diagnostic disable-next-line: param-type-mismatch
		value == "null"
			---@diagnostic disable-next-line: param-type-mismatch
			or vim.startswith(value, '"') and vim.endswith(value, '"')
	)

	local path_arr = ffi.new("const char*[?]", #path)
	for i = 1, #path do
		path_arr[i - 1] = path[i]
	end

	lds.decsync_so_set_entry(connection[0], path_arr, #path, key or "", value)
end

---@param connection Connection
---@param todo tasks.Task
function M.update_todo(connection, todo)
	local uid = todo.uid
	local ical = todo.ical
	local vtodo = todo.vtodo
	local path = { "resources", uid }

	-- TODO: what if as a user I e.g. write into my description "STATUS:NEEDS-ACTION" string? will I inject metadata into the iCal?

	local new_status = vtodo.completed and "COMPLETED" or "NEEDS-ACTION"
	ical = ic.upsert_ical_prop(ical, "STATUS", new_status)

	ical = ic.upsert_ical_prop(ical, "SUMMARY", vtodo.summary)

	local new_cats = { unpack(vtodo.categories) }
	-- NOTE: there is a convention (or at least tasks.org follows it) to sort
	-- categories alphabetically:
	table.sort(new_cats)
	local new_cats_str = table.concat(new_cats, ",")
	ical = ic.upsert_ical_prop(ical, "CATEGORIES", new_cats_str)

	ical = ic.upsert_ical_prop(ical, "PRIORITY", vtodo.priority)

	if vtodo.parent_uid then
		ical =
			ic.upsert_ical_prop(ical, "RELATED-TO;RELTYPE=PARENT", vtodo.parent_uid)
	end

	local ical_json = vim.fn.json_encode(ical)

	---@diagnostic disable-next-line: param-type-mismatch
	M.set_entry(connection, path, nil, ical_json)
end

return M
