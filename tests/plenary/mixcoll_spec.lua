---@diagnostic disable: undefined-field, undefined-global

local mc = require("decscribe.mixcoll")
local tu = require("decscribe.testutil")

local eq = assert.are_same
local ieq = tu.assert_intersections_are_same

describe("to_sorted_list", function()
	local to_sorted_list = mc.to_sorted_list

	it(
		"maps empty collection to empty list",
		function() eq({}, to_sorted_list({})) end
	)

	it(
		"maps singleton collection to singleton list",
		function() eq({ 42 }, to_sorted_list({ 42 })) end
	)

	it(
		"sorts (default comparer) unsorted collection with only unindexed items",
		function() eq({ 42, 69 }, to_sorted_list({ foo = 69, bar = 42 })) end
	)

	it(
		"retains position of indexed item",
		function() eq({ 69, 42 }, to_sorted_list({ [1] = 69, bar = 42 })) end
	)
end)

describe("get_at", function()
	local get_at = mc.get_at
	local comp_fn = function(a, b) return a < b end
	it(
		"given one added item, gets that item from appropriate index",
		function() eq("foo", get_at({ [5] = "foo" }, 5, comp_fn)) end
	)

	it(
		"given one added item, returns nil when out of range",
		function() eq(nil, get_at({ ["foo"] = "bar" }, 2, comp_fn)) end
	)

	it("given two added COMPLEX items, returns one with proper order", function()
		local coll = { foo = { "bar" }, baz = { "kux" } }
		ieq({ "bar" }, get_at(coll, 1, function(a, b) return a[1] < b[1] end))
	end)
end)

describe("delete_at", function()
	local delete_at = mc.delete_at
	local comp_fn = function(a, b) return a < b end
	local id_fn = function(str) return str end

	it(
		"does nothing and returns nil if no item is there",
		function() eq(nil, delete_at({}, 5)) end
	)

	it("deletes existing unsorted item", function()
		local coll = { [2] = "bar" }
		eq("bar", delete_at(coll, 2))
		eq(0, #coll)
	end)

	it("deletes existing sorted item", function()
		local coll = { foo = "bar" }
		eq("bar", delete_at(coll, 1, id_fn, comp_fn))
		eq(0, #coll)
	end)

	it("shifts all further sorted items by one", function()
		local coll = { [3] = "foo", [5] = "bar", [7] = "baz", [9] = "kux" }
		delete_at(coll, 5, id_fn, comp_fn)
		ieq({ [3] = "foo", [6] = "baz", [8] = "kux" }, coll)
	end)
end)

describe("put_at", function()
	local put_at = mc.put_at
	local just_foo_fn = function() return "foo" end
	local lt_comp_fn = function(a, b) return a < b end

	it(
		"returns false if there's nothing at that index",
		function() eq(false, put_at({}, 5, "foo")) end
	)

	it("updates an item explicitly at that index", function()
		local coll = { [5] = "foo" }
		put_at(coll, 5, "bar")
		ieq({ [5] = "bar" }, coll)
	end)

	it("updates an implicit item that happens to be at that index", function()
		local coll = { foo = "bar" }
		put_at(coll, 1, "baz", just_foo_fn, lt_comp_fn)
		ieq({ foo = "baz" }, coll)
	end)
end)

describe("post_at", function()
	local post_at = mc.post_at

	it("adds some item at some index", function()
		local coll = {}
		post_at(coll, 3, "foo")
		ieq({ [3] = "foo" }, coll)
	end)

	it("shifts existing item explicitly at that index forward", function()
		local coll = { [2] = "foo" }
		post_at(coll, 2, "bar")
		ieq({ [2] = "bar", [3] = "foo" }, coll)
	end)

	-- it("does not add if item with given UID already exists in sorted", function ()
	-- error("TODO")
	-- end)

	-- it("does not add if item with given UID already exists in unsorted", function ()
	-- error("TODO")
	-- end)
end)

--[[
describe("delete", function()
	local delete = mc.delete

	it("given one added item, returns that item", function()
		local state = { foo = "bar" }
		eq(delete(state, ))
		delete()
		eq(item, coll:delete(sample_uid1))
	end)

	it("given one added item and deleted, collection is empty", function()
		local coll = {}
		local item = {
			uid = sample_uid1,
			ical = stub_ical,
			vtodo = { completed = false },
		}
		coll:add(sample_uid1, item)
		coll:delete(sample_uid1)
		eq({}, coll)
	end)

	it("deletes unsorted item", function()
		local coll = {}
		local item = {
			uid = sample_uid1,
			ical = stub_ical,
			vtodo = { completed = false },
		}
		coll:add_at(5, item)

		eq(item, coll:delete(sample_uid1))
	end)
end)


describe("update_at", function()
	it("updates this sorted item that happens to be at that index", function()
		local coll = {}
		local item_before = {
			uid = sample_uid1,
			ical = stub_ical,
			vtodo = { completed = false },
		}
		coll:add(item_before.uid, item_before)
		local item_after = {
			uid = sample_uid1,
			ical = stub_ical,
			vtodo = { completed = true },
		}
		coll:update_at(1, item_after.vtodo)
		eq({ item_after }, coll)
	end)

	it("updates this unsorted item that is at that index", function()
		local coll = {}
		local item_before = {
			uid = sample_uid1,
			ical = stub_ical,
			vtodo = { completed = false },
		}
		coll:add_at(5, item_before)
		local item_after = {
			uid = sample_uid1,
			ical = stub_ical,
			vtodo = { completed = true },
		}
		coll:update_at(5, item_after.vtodo)
		eq(item_after, coll[5])
	end)

	it("returns false if there's nothing at that index", function ()
		local coll = {}
		eq(false, coll:update_at(5, { completed = true }))
	end)
end)

describe("uids", function()
	it("returns two UIDs for one sorted and one unsorted item", function()
		local coll = {}
		local task1 = {
			uid = sample_uid1,
			ical = stub_ical,
			vtodo = { completed = false },
		}
		local task2 = {
			uid = sample_uid2,
			ical = stub_ical,
			vtodo = { completed = false },
		}
		coll:add(task1.uid, task1)
		coll:add_at(1, task2)

		local expected = { sample_uid1, sample_uid2 }
		table.sort(expected)
		local actual = coll:uids()
		table.sort(actual)
		eq(expected, actual)
	end)
end)
]]
--
