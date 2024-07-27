---@diagnostic disable: undefined-field, undefined-global

local md = require("decscribe.markdown")
local eq = assert.are_same

describe("decode", function()
	it("ignores blank input", function() eq({}, md.decode("   ")) end)

	it("decodes simple todos", function()
		--- @type decscribe.core.Todo[]
		local exp = {
			{
				completed = true,
				summary = "first",
			},
			{
				completed = false,
				summary = "second",
			},
		}
		eq(
			exp,
			md.decode(table.concat({
				"- [x] first",
				"- [ ] second",
			}, "\n"))
		)
	end)

	it("decodes todos where one has children indented with a tab", function()
		---@type decscribe.core.Todo[]
		local exp = {
			{
				completed = false,
				summary = "parent",
				subtasks = {
					{
						completed = false,
						summary = "child 1",
					},
					{
						completed = true,
						summary = "child 2",
					},
				},
			},
			{
				completed = true,
				summary = "childless",
			},
		}
		eq(
			exp,
			md.decode(table.concat({
				"- [ ] parent",
				"\t- [ ] child 1",
				"\t- [x] child 2",
				"- [x] childless",
			}, "\n"))
		)
	end)

	it("decodes todos with grandchildren", function()
		---@type decscribe.core.Todo[]
		local exp = {
			{
				completed = false,
				summary = "grandparent",
				subtasks = {
					{
						completed = false,
						summary = "parent",
						subtasks = {
							{
								completed = false,
								summary = "child",
							},
						},
					},
				},
			},
		}
		local input = table.concat({
			"- [ ] grandparent",
			"\t- [ ] parent",
			"\t\t- [ ] child",
		}, "\n")
		local act = md.decode(input)
		eq(exp, act)
	end)
end)
