local core = require("decscribe.core")

---@diagnostic disable-next-line: undefined-global
local describe = describe
---@diagnostic disable-next-line: undefined-global
local it = it
---@diagnostic disable-next-line: undefined-field
local eq = assert.are.same
---@diagnostic disable-next-line: undefined-field
local neq = assert.are.not_same

describe("sync_buffer", function()
	local sync_buffer = core.sync_buffer

	it("exists as a function", function() neq(nil, sync_buffer) end)

	it("creates a new todo with a new child todo", function()
		---@type decscribe.core.TempTodo[]
		local next_buf = {
			{ ref = 1, summary = "parent" },
			{ ref = 2, summary = "child", parent_ref = 1 },
		}
		local db_changes, on_db_changed = sync_buffer({}, next_buf)
		eq(next_buf, db_changes)
		local actual_store =
			on_db_changed({ [1] = "parent_uid", [2] = "child_uid" })
		---@type decscribe.core.SavedTodo[]
		local expected_store = {
			{
				uid = "parent_uid",
				summary = "parent",
			},
			{
				uid = "child_uid",
				summary = "child",
				parent_uid = "parent_uid",
			},
		}
		eq(expected_store, actual_store)
	end)
end)
