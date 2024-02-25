---@diagnostic disable: undefined-field, undefined-global

local ic = require("decscribe.ical")

---Like `assert.are_same`, but consider only keys present in both tables.
---@param expected table
---@param actual table
local function assert_intersections_are_same(expected, actual)
	local actual_subset = {}
	for k, v in pairs(actual) do
		if expected[k] ~= nil then actual_subset[k] = v end
	end
	assert.are_same(expected, actual_subset)
end

local ieq = assert_intersections_are_same
local eq = assert.are_same

local function ical_str_from(lines) return table.concat(lines, "\r\n") .. "\r\n" end

describe("find_ical_prop", function()
	local one_prop_data = table.concat({
		"BEGIN:CALENDAR", -- 14 chars + 2 ("\r\n") = 16
		"BEGIN:VTODO", -- 11 chars + 2 ("\r\n") = 13
		"DESCRIPTION:something",
		"END:VTODO",
		"END:CALENDAR",
	}, "\r\n") .. "\r\n"

	it("finds description in the middle of a one-prop ical", function()
		local prop, _, _, _ = ic.find_ical_prop(one_prop_data, "DESCRIPTION")
		eq("something", prop)
	end)

	it("points at the first char of the prop name", function()
		local _, key_i, _, _ = ic.find_ical_prop(one_prop_data, "DESCRIPTION")
		-- 16 + 13 + 1 ("\n" -> "D") = 30
		eq(30, key_i)
	end)

	it("finds description in the middle of multi-prop ical", function()
		local data = table.concat({
			"BEGIN:CALENDAR",
			"BEGIN:VTODO",
			"DESCRIPTION:something",
			"SUMMARY:here",
			"PRIORITY:9",
			"END:VTODO",
			"END:CALENDAR",
		}, "\r\n") .. "\r\n"

		eq("here", ic.find_ical_prop(data, "SUMMARY"))
	end)

	it("finds prop followed by RELATED-TO", function()
		local data = ical_str_from({
			"BEGIN:VCALENDAR",
			"BEGIN:VTODO",
			"SUMMARY:something",
			"RELATED-TO;RELTYPE=PARENT:1234567890",
			"END:VTODO",
			"END:VCALENDAR",
		})
		eq("something", ic.find_ical_prop(data, "SUMMARY"))
	end)
end)

describe("upsert_ical_prop", function()
	it("updates description", function()
		local before = table.concat({
			"BEGIN:CALENDAR",
			"BEGIN:VTODO",
			"DESCRIPTION:something",
			"END:VTODO",
			"END:CALENDAR",
		}, "\r\n") .. "\r\n"
		local after = table.concat({
			"BEGIN:CALENDAR",
			"BEGIN:VTODO",
			"DESCRIPTION:this has changed",
			"END:VTODO",
			"END:CALENDAR",
		}, "\r\n") .. "\r\n"

		eq(after, ic.upsert_ical_prop(before, "DESCRIPTION", "this has changed"))
	end)

	it("inserts description after summary", function()
		local before = ical_str_from({
			"BEGIN:CALENDAR",
			"BEGIN:VTODO",
			"SUMMARY:this does not change",
			"END:VTODO",
			"END:CALENDAR",
		})
		local after = ical_str_from({
			"BEGIN:CALENDAR",
			"BEGIN:VTODO",
			"SUMMARY:this does not change",
			"DESCRIPTION:this is new",
			"END:VTODO",
			"END:CALENDAR",
		})
		eq(after, ic.upsert_ical_prop(before, "DESCRIPTION", "this is new"))
	end)
end)

describe("parse_md_line", function()
	it("rejects a non-checklist line", function()
		local line = "- something"
		eq(nil, ic.parse_md_line(line))
	end)

	it("parses a simple line", function()
		local line = "- [ ] something"
		local actual = ic.parse_md_line(line) or {}
		eq("something", actual.summary)
		eq(false, actual.completed)
	end)

	it("recognizes one category", function()
		local line = "- [ ] :edu: write thesis"
		local expected =
			{ summary = "write thesis", completed = false, categories = { "edu" } }
		ieq(expected, ic.parse_md_line(line) or {})
	end)

	for prio = 1, 9 do
		it("recognizes priority with a number", function()
			local line = ("- [ ] !%d something"):format(prio)
			local expected =
				{ priority = prio, summary = "something", completed = false }
			ieq(expected, ic.parse_md_line(line) or {})
		end)
	end

	for char, num in pairs({
		H = ic.priority_t.tasks_org_high,
		M = ic.priority_t.tasks_org_medium,
		L = ic.priority_t.tasks_org_low,
	}) do
		it("recognizes priority with a letter", function()
			local line = ("- [ ] !%s something"):format(char)
			local expected =
				{ priority = num, summary = "something", completed = false }
			ieq(expected, ic.parse_md_line(line) or {})
		end)
	end

	-- These:
	-- DUE;VALUE=DATE:20201213
	-- DUE;TZID=Europe/Warsaw:20210607T160001
	it("recognizes due date", function()
		local line = "- [ ] 2024-06-15 something with a deadline"
		local expected_ts = os.time({
			year = 2024,
			month = 6,
			day = 15,
		})
		---@type ical.vtodo_t
		local expected = {
			completed = false,
			due = { timestamp = expected_ts, precision = ic.DatePrecision.Date },
			summary = "something with a deadline",
		}
		ieq(expected, ic.parse_md_line(line) or {})
	end)

	-- it("recognizes end datetime")
	-- it("does not recognize end date which is out of bounds ")
	-- it("does not recognize start date which is out of bounds")
	-- it("recognizes start datetime")
end)

describe("ical_parse", function()
	it("parses sample ICal correctly", function()
		local ical = table.concat({
			"BEGIN:CALENDAR",
			"BEGIN:VTODO",
			"PRIORITY:1",
			"STATUS:COMPLETED",
			"SUMMARY:something",
			"X-OC-HIDESUBTASKS:1",
			"DUE;VALUE=DATE:20240612",
			"END:VTODO",
			"END:CALENDAR",
		}, "\r\n") .. "\r\n"
		local expected = {
			{ key = "BEGIN", value = "CALENDAR" },
			{ key = "BEGIN", value = "VTODO" },
			{ key = "PRIORITY", value = "1" },
			{ key = "STATUS", value = "COMPLETED" },
			{ key = "SUMMARY", value = "something" },
			{ key = "X-OC-HIDESUBTASKS", value = "1" },
			{ key = "DUE", value = "20240612", opts = { VALUE = "DATE" } },
			{ key = "END", value = "VTODO" },
			{ key = "END", value = "CALENDAR" },
		}
		eq(expected, ic.ical_parse(ical))
	end)

	it("parses Ical with a multiline value", function()
		local ical = table.concat({
			"BEGIN:CALENDAR",
			"BEGIN:VTODO",
			"STATUS:COMPLETED",
			"SUMMARY:something",
			"DESCRIPTION:this",
			"is a multiline",
			"description",
			"END:VTODO",
			"END:CALENDAR",
		}, "\r\n") .. "\r\n"
		local expected = {
			{ key = "BEGIN", value = "CALENDAR" },
			{ key = "BEGIN", value = "VTODO" },
			{ key = "STATUS", value = "COMPLETED" },
			{ key = "SUMMARY", value = "something" },
			{ key = "DESCRIPTION", value = "this\r\nis a multiline\r\ndescription" },
			{ key = "END", value = "VTODO" },
			{ key = "END", value = "CALENDAR" },
		}
		eq(expected, ic.ical_parse(ical))
	end)
end)

describe("ical_show", function()
	it("show a sample Ical correctly", function()
		local input = {
			{ key = "BEGIN", value = "CALENDAR" },
			{ key = "BEGIN", value = "VTODO" },
			{ key = "PRIORITY", value = "1" },
			{ key = "STATUS", value = "COMPLETED" },
			{ key = "SUMMARY", value = "something" },
			{ key = "X-OC-HIDESUBTASKS", value = "1" },
			{ key = "DUE", value = "20240612", opts = { VALUE = "DATE" } },
			{ key = "END", value = "VTODO" },
			{ key = "END", value = "CALENDAR" },
		}
		local expected = table.concat({
			"BEGIN:CALENDAR",
			"BEGIN:VTODO",
			"PRIORITY:1",
			"STATUS:COMPLETED",
			"SUMMARY:something",
			"X-OC-HIDESUBTASKS:1",
			"DUE;VALUE=DATE:20240612",
			"END:VTODO",
			"END:CALENDAR",
		}, "\r\n") .. "\r\n"
		eq(expected, ic.ical_show(input))
	end)
end)
