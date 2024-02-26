local app = require("decscribe.app")
local ts = require("decscribe.tasks")
local ic = require("decscribe.ical")

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

	it("reads a task with a priority and a due date", function()
		-- given
		local state = {
			lines = {},
			tasks = ts.Tasks:new(),
		}
		-- when
		local actual_lines = nil
		app.read_buffer(state, {
			ui = {
				buf_set_opt = function() end,
				buf_get_lines = function() return {} end,
				buf_set_lines = function(_, _, lines) actual_lines = lines end,
			},
			db_retrieve_icals = function()
				return {
					["1234"] = table.concat({
						"BEGIN:CALENDAR",
						"BEGIN:VTODO",
						"PRIORITY:1",
						"STATUS:NEEDS-ACTION",
						"SUMMARY:something",
						"DUE;VALUE=DATE:20240415",
						"END:VTODO",
						"END:CALENDAR",
					}, "\r\n") .. "\r\n",
				}
			end,
		})
		-- then
		eq({ "- [ ] 2024-04-15 !H something" }, actual_lines)
	end)
end)

describe("write_buffer", function()
	it("writes a task with a due date insert", function()
		-- given
		---@type decscribe.State
		local state = {
			lines = { "- [ ] !H something" },
			tasks = ts.Tasks:new(),
		}
		state.tasks:add("1234", {
			uid = "1234",
			ical = table.concat({
				"BEGIN:CALENDAR",
				"BEGIN:VTODO",
				"PRIORITY:1",
				"STATUS:NEEDS-ACTION",
				"SUMMARY:something",
				"END:VTODO",
				"END:CALENDAR",
			}, "\r\n") .. "\r\n",
			vtodo = {
				summary = "something",
				completed = false,
				priority = ic.priority_t.tasks_org_high,
			},
		})
		-- when
		local updated_ical = nil
		app.write_buffer(state, {
			ui = {
				buf_set_lines = function() end,
				buf_get_lines = function() return { "- [ ] 2024-04-12 !H something" } end,
				buf_set_opt = function() end,
			},
			db_delete_ical = function() end,
			db_update_ical = function(_, ical)
				updated_ical = ical
				-- due = { precision = ic.DatePrecision.Date, timestamp = os.time({ year = }) }
			end,
		})
		eq(table.concat({
			"BEGIN:CALENDAR",
			"BEGIN:VTODO",
			"PRIORITY:1",
			"STATUS:NEEDS-ACTION",
			"SUMMARY:something",
			"DUE;VALUE=DATE:20240412",
			"END:VTODO",
			"END:CALENDAR",
		}, "\r\n") .. "\r\n", updated_ical)
	end)

	it("writes a task with a due date update", function()
		-- given
		---@type decscribe.State
		local state = {
			lines = { "- [ ] 2024-04-15 !H something" },
			tasks = ts.Tasks:new(),
		}
		state.tasks:add("1234", {
			uid = "1234",
			ical = table.concat({
				"BEGIN:CALENDAR",
				"BEGIN:VTODO",
				"PRIORITY:1",
				"DUE;VALUE=DATE:20240415",
				"STATUS:NEEDS-ACTION",
				"SUMMARY:something",
				"END:VTODO",
				"END:CALENDAR",
			}, "\r\n") .. "\r\n",
			vtodo = {
				summary = "something",
				completed = false,
				priority = ic.priority_t.tasks_org_high,
				due = {
					precision = ic.DatePrecision.Date,
					timestamp = os.time({ year = 2024, month = 04, day = 15 }),
				},
			},
		})
		-- when
		local updated_ical = nil
		app.write_buffer(state, {
			ui = {
				buf_set_lines = function() end,
				buf_get_lines = function() return { "- [ ] 2024-04-18 !H something" } end,
				buf_set_opt = function() end,
			},
			db_delete_ical = function() end,
			db_update_ical = function(_, ical) updated_ical = ical end,
		})
		eq(table.concat({
			"BEGIN:CALENDAR",
			"BEGIN:VTODO",
			"PRIORITY:1",
			"DUE;VALUE=DATE:20240418",
			"STATUS:NEEDS-ACTION",
			"SUMMARY:something",
			"END:VTODO",
			"END:CALENDAR",
		}, "\r\n") .. "\r\n", updated_ical)
	end)

	it("writes a task with a due date removal", function()
		-- given
		---@type decscribe.State
		local state = {
			lines = { "- [ ] 2024-04-15 !H something" },
			tasks = ts.Tasks:new(),
		}
		state.tasks:add("1234", {
			uid = "1234",
			ical = table.concat({
				"BEGIN:CALENDAR",
				"BEGIN:VTODO",
				"PRIORITY:1",
				"DUE;VALUE=DATE:20240415",
				"STATUS:NEEDS-ACTION",
				"SUMMARY:something",
				"END:VTODO",
				"END:CALENDAR",
			}, "\r\n") .. "\r\n",
			vtodo = {
				summary = "something",
				completed = false,
				priority = ic.priority_t.tasks_org_high,
				due = {
					precision = ic.DatePrecision.Date,
					timestamp = os.time({ year = 2024, month = 04, day = 15 }),
				},
			},
		})
		-- when
		local updated_ical = nil
		app.write_buffer(state, {
			ui = {
				buf_set_lines = function() end,
				buf_get_lines = function() return { "- [ ] !H something" } end,
				buf_set_opt = function() end,
			},
			db_delete_ical = function() end,
			db_update_ical = function(_, ical) updated_ical = ical end,
		})
		eq(table.concat({
			"BEGIN:CALENDAR",
			"BEGIN:VTODO",
			"PRIORITY:1",
			"STATUS:NEEDS-ACTION",
			"SUMMARY:something",
			"END:VTODO",
			"END:CALENDAR",
		}, "\r\n") .. "\r\n", updated_ical)
	end)

	it("writes a task with category removal", function()
		-- given
		---@type decscribe.State
		local state = {
			lines = { "- [ ] :first: :second: something" },
			tasks = ts.Tasks:new(),
		}
		state.tasks:add("1234", {
			uid = "1234",
			ical = table.concat({
				"BEGIN:CALENDAR",
				"BEGIN:VTODO",
				"STATUS:NEEDS-ACTION",
				"SUMMARY:something",
				"CATEGORIES:first,second",
				"END:VTODO",
				"END:CALENDAR",
			}, "\r\n") .. "\r\n",
			vtodo = {
				summary = "something",
				completed = false,
				priority = ic.priority_t.tasks_org_high,
			},
		})
		-- when
		local updated_ical = nil
		app.write_buffer(state, {
			ui = {
				buf_set_lines = function() end,
				buf_get_lines = function() return { "- [ ] something" } end,
				buf_set_opt = function() end,
			},
			db_delete_ical = function() end,
			db_update_ical = function(_, ical) updated_ical = ical end,
		})
		eq(table.concat({
			"BEGIN:CALENDAR",
			"BEGIN:VTODO",
			"STATUS:NEEDS-ACTION",
			"SUMMARY:something",
			"END:VTODO",
			"END:CALENDAR",
		}, "\r\n") .. "\r\n", updated_ical)
	end)
end)
