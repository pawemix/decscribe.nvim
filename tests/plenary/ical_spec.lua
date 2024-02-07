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
end)
