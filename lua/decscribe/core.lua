local di = require("decscribe.diff")

local M = {}

---@alias decscribe.core.Uid string
---Used as synthetic public key to uniquely distinguish each todo.

---@alias decscribe.core.TempRef integer
---Used in not-yet-persisted Todos to show relations between each other.
---After syncing with a database shall be replaced with a proper Uid.

---@alias decscribe.core.Removed false

---@class (exact) decscribe.core.Saved
---@field uid decscribe.core.Uid

---@class (exact) decscribe.core.TodoDiff
---This gets sent into the database for patching.
---@field completed? boolean | decscribe.core.Removed
---@field summary? string | decscribe.core.Removed
---@field parent_ref? decscribe.core.TempRef | decscribe.core.Removed
---@field parent_uid? decscribe.core.Uid | decscribe.core.Removed

---@class (exact) decscribe.core.Todo
---A data structure on its own without any relations.
---@field completed? boolean `false` by default
---@field summary? string empty by default
---@field description? string
---@field categories? string[]
---@field dtstart decscribe.date.Date?
---@field due decscribe.date.Date?

---@param todo decscribe.core.Todo
---@param ref decscribe.core.TempRef
---@return decscribe.core.TempTodo
function M.with_ref(todo, ref)
	return vim.tbl_extend("force", todo, { ref = ref })
end

---@param tt decscribe.core.TempTodo
---@return decscribe.core.Todo todo
function M.unref(tt)
	local todo = {}
	for k, v in pairs(tt) do
		todo[k] = v
	end
	todo.ref = nil
	return todo
end

---@param st decscribe.core.SavedTodo
---@return decscribe.core.Todo todo
function M.unuid(st)
	local todo = {}
	for k, v in pairs(st) do
		todo[k] = v
	end
	todo.uid = nil
	return todo
end

---@param todo decscribe.core.Todo
---@param uid decscribe.core.Uid
---@return decscribe.core.SavedTodo
function M.with_uid(todo, uid)
	---@type decscribe.core.SavedTodo
	local st = { uid = uid }
	for k, v in pairs(todo) do
		st[k] = v
	end
	return st
end

---@class (exact) decscribe.core.TempTodo
---@field ref decscribe.core.TempRef
---@field completed? boolean `false` by default
---@field summary? string empty by default
---@field parent_ref? decscribe.core.TempRef if the parent is also not save
---@field parent_uid? decscribe.core.Uid if the parent is saved

---@class (exact) decscribe.core.SavedTodo
---@field uid decscribe.core.Uid
---@field completed? boolean `false` by default
---@field summary? string empty by default
---@field parent_uid? decscribe.core.Uid

---@param tt decscribe.core.TempTodo
---@param uid decscribe.core.Uid
---@param refs_to_uids { [decscribe.core.TempRef]: decscribe.core.Uid }
---@return decscribe.core.SavedTodo st
function M.tt2st(tt, uid, refs_to_uids)
	local parent_uid = tt.parent_uid
	if tt.parent_ref then
		parent_uid = assert(
			refs_to_uids[tt.parent_ref],
			"TempTodo's parent's TempRef wasn't resolved to a UID!"
		)
	end
	local st = {}
	for k, v in pairs(tt) do
		st[k] = v
	end
	st.ref = nil
	st.parent_ref = nil
	st.uid = uid
	st.parent_uid = parent_uid
	return st
end

---@param sts decscribe.core.SavedTodo[]
---@return decscribe.core.TempTodo[] tts
function M.sts2tts(sts)
	local uids_to_refs = {}
	-- XXX: calculates refs based on ORDER of the sts!
	for ref, st in ipairs(sts) do
		uids_to_refs[st.uid] = ref
	end
	--
	local tts = {}
	for ref, st in ipairs(sts) do
		---@type decscribe.core.TempTodo
		local tt = { ref = ref }
		for k, v in pairs(st) do
			if k ~= "uid" and k ~= "parent_uid" then tt[k] = v end
		end
		if st.parent_uid then tt.parent_ref = uids_to_refs[st.parent_uid] end
		tts[ref] = tt
	end
	--
	return tts
end

---@generic Todo: decscribe.core.Saved
---@param ts Todo[]
---@return { [decscribe.core.Uid]: Todo }
function M.group_by_uid(ts)
	local out = {}
	for _, t in ipairs(ts) do
		out[t.uid] = t
	end
	return out
end

---@param td decscribe.core.TodoDiff
---@param ref decscribe.core.TempRef
---@param refs_to_uids { [decscribe.core.TempRef]: decscribe.core.Uid }
---@return decscribe.core.TempTodo
function M.td2tt(td, ref, refs_to_uids)
	---@type decscribe.core.TempTodo
	local tt = vim.tbl_extend("force", td, { ref = ref })
	tt.parent_uid = refs_to_uids[tt.parent_ref] or tt.parent_uid
	if tt.parent_uid then tt.parent_ref = nil end
	return tt
end

---@alias decscribe.core.TodoStore
---This is stored in memory after every buffer-database sync.
---| decscribe.core.SavedTodo[]

---@alias decscribe.core.DbChange
---| { [decscribe.core.Uid]: decscribe.core.TodoDiff | decscribe.core.Removed, [integer]: decscribe.core.TempTodo }

---@alias decscribe.core.DbResult
---| { [decscribe.core.TempRef]: decscribe.core.Uid }

---@alias decscribe.core.DbChangeCont
---| fun(db_result: decscribe.core.DbResult): decscribe.core.SavedTodo[]

---@param curr_store decscribe.core.TodoStore Retrieved from in-memory store.
---@param next_buf decscribe.core.TempTodo[] Retrieved from parsing the buffer.
---@return decscribe.core.DbChange[] db_changes
---@return decscribe.core.DbChangeCont on_db_changed
---
---# Example Usage
---```lua
---local db_changes, on_db_changed = sync_buffer(before, after)
---local db_result = db.commit_db_changes(db_changes)
---local buf_synced = on_db_changed(db_result)
---```
function M.sync_buffer(curr_store, next_buf)
	---@type decscribe.core.TempTodo[]
	---Discard PersistedTodo-specific fields to not disrupt the diffing process.
	local curr_buf = M.sts2tts(curr_store)
	---@type decscribe.core.DbChange
	local db_changes = {}
	---@type { [decscribe.core.TempRef]: decscribe.core.Uid }
	local refs_to_uids = {}
	for ref, st in ipairs(curr_store) do
		refs_to_uids[ref] = st.uid
	end
	--
	local todos_diff = di.diff(curr_buf, next_buf)
	---@cast todos_diff decscribe.core.TodoDiff[]
	for pos, todo_diff in pairs(todos_diff) do
		local curr_todo = curr_store[pos]
		if curr_todo then
			if todo_diff == di.Removal then -- task has been removed
				db_changes[curr_todo.uid] = false
			else -- task has been modified
				db_changes[curr_todo.uid] = todo_diff
			end
		else -- new task was created
			local new_todo = M.td2tt(todo_diff, pos, refs_to_uids)
			db_changes[#db_changes + 1] = new_todo
		end
	end

	return db_changes,
		function(db_result)
			---@type decscribe.core.TodoStore
			local next_store = {}
			-- Load the unchaged todos from te current store first:
			for k, v in pairs(curr_store) do
				next_store[k] = v
			end
			for ref, uid in ipairs(db_result) do
				local new_todo = db_changes[ref]
				local new_todo_saved = M.tt2st(new_todo, uid, db_result)
				next_store[#next_store + 1] = new_todo_saved
			end
			--
			return next_store
		end
end

return M
