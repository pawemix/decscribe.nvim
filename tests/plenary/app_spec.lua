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
		local actual_lines = app.read_buffer(state, {
			icals = {
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
		local actual_lines = app.read_buffer(state, {
			icals = {
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
			ical,
			app.write_buffer({
				lines = {},
				tasks = ts.Tasks:new(),
			}, {
				new_lines = { "- [ ] first task" },
				fresh_timestamp = created.stamp,
				seed = seed,
			}).changes[uid]
		)
	end)

	it("deletes a simple task", function()
		-- given
		local state = {
			lines = { "- [ ] something" },
			tasks = ts.Tasks:new(),
		}
		state.tasks:add("1234", {
			uid = "1234",
			vtodo = { completed = false, summary = "something" },
			ical = to_ical({
				"BEGIN:VTODO",
				"STATUS:NEEDS-ACTION",
				"SUMMARY:something",
				"END:VTODO",
			}),
		})
		-- when & then
		eq(
			{ ["1234"] = false },
			app.write_buffer(state, { new_lines = {} }).changes
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
		local actual = app.write_buffer(state, {
			new_lines = { "- [ ] 2024-04-12 !H something" },
		})
		eq(
			to_ical({
				"BEGIN:CALENDAR",
				"BEGIN:VTODO",
				"PRIORITY:1",
				"STATUS:NEEDS-ACTION",
				"SUMMARY:something",
				"DUE;VALUE=DATE:20240412",
				"END:VTODO",
				"END:CALENDAR",
			}),
			actual.changes["1234"]
		)
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
		local actual = app.write_buffer(state, {
			new_lines = { "- [ ] 2024-04-18 !H something" },
		})
		eq(
			to_ical({
				"BEGIN:CALENDAR",
				"BEGIN:VTODO",
				"PRIORITY:1",
				"DUE;VALUE=DATE:20240418",
				"STATUS:NEEDS-ACTION",
				"SUMMARY:something",
				"END:VTODO",
				"END:CALENDAR",
			}),
			actual.changes["1234"]
		)
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
		local actual = app.write_buffer(state, {
			new_lines = { "- [ ] !H something" },
		})
		eq(
			to_ical({
				"BEGIN:CALENDAR",
				"BEGIN:VTODO",
				"PRIORITY:1",
				"STATUS:NEEDS-ACTION",
				"SUMMARY:something",
				"END:VTODO",
				"END:CALENDAR",
			}),
			actual.changes["1234"]
		)
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
		local actual = app.write_buffer(state, {
			new_lines = { "- [ ] something" },
		})
		eq(
			to_ical({
				"BEGIN:CALENDAR",
				"BEGIN:VTODO",
				"STATUS:NEEDS-ACTION",
				"SUMMARY:something",
				"END:VTODO",
				"END:CALENDAR",
			}),
			actual.changes["1234"]
		)
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
		local actual = app.write_buffer(state, {
			new_lines = { "- [ ] 2024-04-15 09:06 something" },
		})
		eq(
			to_ical({
				"BEGIN:CALENDAR",
				"BEGIN:VTODO",
				"STATUS:NEEDS-ACTION",
				"SUMMARY:something",
				"DUE;TZID=America/Chicago:20240415T090600",
				"END:VTODO",
				"END:CALENDAR",
			}),
			actual.changes["1234"]
		)
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
		local actual = app.write_buffer(state, {
			new_lines = { "- [ ] " .. new_due_md .. " something" },
			seed = 42,
			fresh_timestamp = created_tstamp,
		})
		eq({ [new_uid] = new_ical }, actual.changes)
	end)

	it("updates with a due datetime update", function()
		-- given
		local uid = ic.generate_uid({}, 42)
		local due_tstamp = 1555774440
		local due_md = "2019-04-20 15:34"
		local due_ical = "20190420T153400"
		local created_tstamp = 1555774466
		local line = "- [ ] " .. due_md .. " something"
		---@type ical.vtodo_t
		local vtodo = {
			completed = false,
			due = {
				precision = ic.DatePrecision.DateTime,
				timestamp = due_tstamp,
			},
		}
		local ical = to_ical({
			"BEGIN:VTODO",
			"STATUS:NEEDS-ACTION",
			"SUMMARY:something",
			"DUE;TZID=America/Chicago:" .. due_ical,
			"END:VTODO",
		})
		---@type decscribe.State
		local state = {
			tzid = "America/Chicago",
			lines = { line },
			tasks = ts.Tasks:new(),
		}
		state.tasks:add(uid, { uid = uid, vtodo = vtodo, ical = ical })
		-- when
		local actual = app.write_buffer(state, {
			new_lines = { "- [ ] 2024-04-15 16:09 something" },
			seed = 42,
			fresh_timestamp = created_tstamp,
		})
		-- then
		local new_due_ical = "20240415T160900"
		local new_ical = to_ical({
			"BEGIN:VTODO",
			"STATUS:NEEDS-ACTION",
			"SUMMARY:something",
			"DUE;TZID=America/Chicago:" .. new_due_ical,
			"END:VTODO",
		})
		eq({ [uid] = new_ical }, actual.changes)
	end)
end)
