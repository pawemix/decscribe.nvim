local app = require("decscribe.app")
local ts = require("decscribe.tasks")

---@diagnostic disable-next-line: undefined-global
local describe = describe
---@diagnostic disable-next-line: undefined-global
local it = it
---@diagnostic disable-next-line: undefined-field
local eq = assert.are_same

describe("read_buffer", function()
	it("reads correctly a task with X-OC-HIDESUBTASKS ical prop", function()
		-- given
		---@type decscribe.State
		local state = {
			lines = {},
			tasks = ts.Tasks:new(),
		}
		-- when
		local actual_lines = nil
		app.read_buffer(state, {
			db_retrieve_icals = function()
				return {
					["1234"] = table.concat({
						"BEGIN:CALENDAR",
						"BEGIN:VTODO",
						"PRIORITY:1",
						"STATUS:COMPLETED",
						"SUMMARY:something",
						"X-OC-HIDESUBTASKS:1",
						"END:VTODO",
						"END:CALENDAR",
					}, "\r\n"),
				}
			end,
			ui = {
				buf_set_opt = function() end,
				buf_get_lines = function() error("should not be called") end,
				buf_set_lines = function(_, _, lines) actual_lines = lines end,
			},
		})
		-- then
		eq({ "- [x] !H something" }, actual_lines)
	end)
end)
