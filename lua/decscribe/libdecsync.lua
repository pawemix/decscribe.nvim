local ffi = nil
local lds = nil

local M = {}

---@enum SyncType
M.SyncType = {
	tasks = "tasks",
	-- ... TODO
}


function M.check_decsync_info(decsync_dir)
	ffi = ffi or require("ffi")
	lds = lds or ffi.load("libdecsync")
	ffi.cdef([[
		static int decsync_so_check_decsync_info(const char* decsync_dir);
	]])
	return lds.decsync_so_check_decsync_info(decsync_dir)
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

	print(collections_count)
	-- accumulate the collections from C array to Lua table
	local collections = {}
	for idx = 0, collections_count - 1 do
		local collection = ffi.string(collections_ref[idx])
		table.insert(collections, collection)
	end

	return collections
end

function M.update_todo(todo)
	local uid = todo.uid
	local vcal = todo.vcal
	-- transform json into vcal
	-- decsync.set_entry()
end

return M
