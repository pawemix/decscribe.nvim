---@diagnostic disable: undefined-field, undefined-global

local ic = require("decscribe.ical")

local eq = assert.are_same

describe("find_ical_prop", function()
	it("finds description in the middle of a one-prop ical", function()
		local data = table.concat({
			"BEGIN:CALENDAR",
			"BEGIN:VTODO",
			"DESCRIPTION:something",
			"END:VTODO",
			"END:CALENDAR",
		}, "\r\n") .. "\r\n"

		eq("something", ic.find_ical_prop(data, "DESCRIPTION"))
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
