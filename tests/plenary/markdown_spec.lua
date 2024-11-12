---@diagnostic disable: undefined-field, undefined-global

local md = require("decscribe.markdown")
local eq = assert.are_same

describe("decode", function()
	it("ignores blank input", function() eq({}, md.decode("   ")) end)

	it("decodes simple todos", function()
		--- @type decscribe.core.TempTodo[]
		local exp = {
			{
				ref = 1,
				completed = true,
				summary = "first",
			},
			{
				ref = 2,
				-- completed = false,
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
		---@type decscribe.core.TempTodo[]
		local exp = {
			{
				ref = 1,
				-- completed = false,
				summary = "parent",
			},
			{
				ref = 2,
				-- completed = false,
				summary = "child 1",
				parent_ref = 1,
			},
			{
				ref = 3,
				completed = true,
				summary = "child 2",
				parent_ref = 1,
			},
			{
				ref = 4,
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
		---@type decscribe.core.TempTodo[]
		local exp = {
			{
				ref = 1,
				-- completed = false,
				summary = "grandparent",
			},
			{
				ref = 2,
				-- completed = false,
				summary = "parent",
				parent_ref = 1,
			},
			{
				ref = 3,
				-- completed = false,
				summary = "child",
				parent_ref = 2,
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

describe("todo2str", function()
	it("renders dtstart datetime with timezone", function()
		local date = os.time({
			year = 2017,
			month = 6,
			day = 2,
			hour = 15,
			min = 30,
		})
		---@type decscribe.core.Todo
		local input_todo = {
			summary = "summary",
			dtstart = { precision = "DATETIME", timestamp = date },
		}
		local expected = "- [ ] 2017-06-02 15:30.. summary"
		eq(expected, md.todo2str(input_todo))
	end)
end)
