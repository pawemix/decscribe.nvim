local app = require("decscribe.app")
local ts = require("decscribe.tasks")
local ic = require("decscribe.ical")

---@diagnostic disable-next-line: undefined-global
local describe = describe
---@diagnostic disable-next-line: undefined-global
local it = it
---@diagnostic disable-next-line: undefined-field
local eq = assert.are_same

---@param lines string[]
---@return ical.ical_t
local function to_ical(lines) return table.concat(lines, "\r\n") .. "\r\n" end

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
	it("creates a simple task", function()
		local seed = 1337
		local uid = ic.generate_uid({}, seed)
		local created = {
			date = "20240301T133320Z",
			stamp = 1709300000, -- `$ date +%s --date=2024-03-01T13:33:20Z`
		}
		local ical = to_ical({
			"BEGIN:VCALENDAR",
			"VERSION:2.0",
			"BEGIN:VTODO",
			"PRODID:decscribe",
			"DTSTAMP:" .. created.date,
			"UID:" .. uid,
			"CREATED:" .. created.date,
			"LAST-MODIFIED:" .. created.date,
			"SUMMARY:first task",
			"PRIORITY:0",
			"STATUS:NEEDS-ACTION",
			"CATEGORIES:",
			"COMPLETED:" .. created.date,
			"PERCENT-COMPLETE:0",
			"END:VTODO",
			"END:VCALENDAR",
		})
		eq(
			{ to_create = { [uid] = ical } },
			app.write_buffer({
				lines = {},
				tasks = ts.Tasks:new(),
			}, {
				new_lines = { "- [ ] first task" },
				fresh_timestamp = created.stamp,
				seed = seed,
			})
		)
	end)

	it("updates a due date insert", function()
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

	it("updates a due date update", function()
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

	it("updates a due date removal", function()
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

	it("updates a category removal", function()
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

	it("updates a due datetime (up to minutes) insert", function()
		-- given
		---@type decscribe.State
		local state = {
			tzid = "America/Chicago",
			lines = { "- [ ] something" },
			tasks = ts.Tasks:new(),
		}
		state.tasks:add("1234", {
			uid = "1234",
			ical = table.concat({
				"BEGIN:CALENDAR",
				"BEGIN:VTODO",
				"STATUS:NEEDS-ACTION",
				"SUMMARY:something",
				"END:VTODO",
				"END:CALENDAR",
			}, "\r\n") .. "\r\n",
			vtodo = {
				summary = "something",
				completed = false,
			},
		})
		-- when
		local updated_ical = nil
		app.write_buffer(state, {
			ui = {
				buf_set_lines = function() end,
				buf_get_lines = function()
					return { "- [ ] 2024-04-15 09:06 something" }
				end,
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
			"DUE;TZID=America/Chicago:20240415T090600",
			"END:VTODO",
			"END:CALENDAR",
		}, "\r\n") .. "\r\n", updated_ical)
	end)

	it("creates with a due datetime insert", function()
		-- given
		---@type decscribe.State
		local state = {
			tzid = "America/Chicago",
			lines = {},
			tasks = ts.Tasks:new(),
		}
		local new_due_md = "2023-07-12 06:34"
		local new_due_ic = "20230712T063400"
		local created_tstamp = 1555774466
		local created_datetime = "20190420T153426Z"
		local new_uid = ic.generate_uid({}, 42)
		local new_ical = table.concat({
			"BEGIN:VCALENDAR",
			"VERSION:2.0",
			"BEGIN:VTODO",
			"PRODID:decscribe",
			"DTSTAMP:" .. created_datetime,
			"UID:" .. new_uid,
			"CREATED:" .. created_datetime,
			"LAST-MODIFIED:" .. created_datetime,
			"SUMMARY:something",
			"PRIORITY:0", -- TODO: remove
			"STATUS:NEEDS-ACTION",
			"CATEGORIES:", -- TODO: remove
			"COMPLETED:" .. created_datetime, -- TODO: remove
			"PERCENT-COMPLETE:0", -- TODO: remove
			"DUE;TZID=America/Chicago:" .. new_due_ic,
			"END:VTODO",
			"END:VCALENDAR",
		}, "\r\n") .. "\r\n"
		local actual = app.write_buffer(
			state,
			{
				new_lines = { "- [ ] " .. new_due_md .. " something" },
				seed = 42,
				fresh_timestamp = created_tstamp,
			}
		)
		eq({ [new_uid] = new_ical } , actual.to_create)
	end)

	-- TODO: update due datetime update
end)
