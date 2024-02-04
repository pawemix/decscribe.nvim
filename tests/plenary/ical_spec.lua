---@diagnostic disable: undefined-field, undefined-global

local ic = require("decscribe.ical")

local eq = assert.are_same

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

	it("points at the first char of the prop name", function ()
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
end)
