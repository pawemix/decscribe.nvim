---@diagnostic disable: undefined-field, undefined-global

local di = require("decscribe.diff")

local eq = assert.are_same

describe("diff", function()

	it("shows removed field as Removal constant", function()
		local before = { foo = "bar", baz = "kux" }
		local after = { foo = "bar" }
		local exp = { baz = di.Removal }
		eq(exp, di.diff(before, after))
	end)

	it("shows changed field", function()
		local before = { foo = "foo" }
		local after = { foo = "bar" }
		local exp = { foo = "bar" }
		eq(exp, di.diff(before, after))
	end)

	it("shows deeply changed table field recursively", function()
		local before = { foo = { unchanged = "baz", bar = "before" } }
		local after = { foo = { unchanged = "baz", bar = "after" } }
		local exp = { foo = { bar = "after" } }
		eq(exp, di.diff(before, after))
	end)

	it("recognizes removed items in a list", function()
		local before = { "first", "second", "third", "fourth" }
		local after = { "first", "fourth" }
		local exp = { [2] = di.Removal, [3] = di.Removal }
		eq(exp, di.diff(before, after))
	end)

	it("recognizes a block of changed elements in list", function()
		local before = { "first", "second", "third", "fourth" }
		local after = { "first", "second_changed", "third_changed", "fourth" }
		local exp = { [2] = "second_changed", [3] = "third_changed" }
		eq(exp, di.diff(before, after))
	end)

	it("ignores unchanged fields of a table item of a list", function ()
		local before = { "first", { unchanged = "foo", bar = "before"}}
		local after = { "first", { unchanged = "foo", bar = "after"}}
		local exp = { [2] = { bar = "after" } }
		eq(exp, di.diff(before, after))
	end)
end)
