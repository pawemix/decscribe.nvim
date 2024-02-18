local testutil = require("decscribe.testutil")

local deq = testutil.assert_intersections_are_same
---@diagnostic disable-next-line: undefined-global
local describe = describe
---@diagnostic disable-next-line: undefined-global
local it = it
---@diagnostic disable-next-line: undefined-field
local eq = assert.are.same
---@diagnostic disable-next-line: undefined-field
local isnil = assert.is_nil

local ts = require("decscribe.tasks")

describe("Tasks", function()
	local sample_uid1 = "1234"
	local sample_uid2 = "5678"
	local sample_uid3 = "9012"
	local stub_ical = "BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n"
	local function vtodo_comp_unchecked_first(vtodo1, vtodo2)
		return (vtodo1.completed and 1 or 0) < (vtodo2.completed and 1 or 0)
	end
	local function vtodo_comp_uncecked_first_then_summary_alpha(vtodo1, vtodo2)
		local summary1 = vtodo1.summary or ""
		local summary2 = vtodo2.summary or ""
		if summary1 ~= summary2 then return summary1 < summary2 end
		return (vtodo1.completed and 1 or 0) < (vtodo2.completed and 1 or 0)
	end

	describe("new", function()
		it("gets created and returns an empty list", function()
			local tasks = ts.Tasks:new()
			deq({}, tasks:to_list())
		end)
	end)

	describe("add", function()
		it("adds one task", function()
			local tasks = ts.Tasks:new()
			---@type tasks.Task
			local task = {
				uid = sample_uid1,
				ical = stub_ical,
				vtodo = { completed = false },
			}

			tasks:add(sample_uid1, task)

			deq({ task }, tasks:to_list())
		end)

		it("adds two tasks in correct order", function()
			local tasks = ts.Tasks:new({
				vtodo_comp = vtodo_comp_unchecked_first,
			})
			---@type tasks.Task
			local task1 = {
				uid = sample_uid1,
				ical = stub_ical,
				vtodo = { completed = true },
			}
			---@type tasks.Task
			local task2 = {
				uid = sample_uid2,
				ical = stub_ical,
				vtodo = { completed = false },
			}
			tasks:add(task1.uid, task1)
			tasks:add(task2.uid, task2)
			deq({ task2, task1 }, tasks:to_list())
		end)

		-- it("does not add if task with given UID already exists in sorted", function ()
			-- error("TODO")
		-- end)

		-- it("does not add if task with given UID already exists in unsorted", function ()
			-- error("TODO")
		-- end)
	end)

	describe("get_at", function()
		it("given one added task, gets that task from index 1", function()
			local tasks = ts.Tasks:new()
			---@type tasks.Task
			local task1 = {
				uid = sample_uid1,
				ical = stub_ical,
				vtodo = { completed = false },
			}
			tasks:add(sample_uid1, task1)
			eq(task1, tasks:get_at(1))
		end)

		it("given one added task, returns nil when out of range", function()
			local tasks = ts.Tasks:new()
			---@type tasks.Task
			local task1 = {
				uid = sample_uid1,
				ical = stub_ical,
				vtodo = { completed = false },
			}
			tasks:add(sample_uid1, task1)
			eq(nil, tasks:get_at(2))
		end)
	end)

	describe("delete", function()
		it("given one added task and deleted, returns that task", function()
			local tasks = ts.Tasks:new()
			---@type tasks.Task
			local task = {
				uid = sample_uid1,
				ical = stub_ical,
				vtodo = { completed = false },
			}
			tasks:add(sample_uid1, task)
			eq(task, tasks:delete(sample_uid1))
		end)

		it("given one added task and deleted, to_list is empty", function()
			local tasks = ts.Tasks:new()
			---@type tasks.Task
			local task = {
				uid = sample_uid1,
				ical = stub_ical,
				vtodo = { completed = false },
			}
			tasks:add(sample_uid1, task)
			tasks:delete(sample_uid1)
			eq({}, tasks:to_list())
		end)

		it("deletes unsorted task", function()
			local tasks = ts.Tasks:new()
			---@type tasks.Task
			local task = {
				uid = sample_uid1,
				ical = stub_ical,
				vtodo = { completed = false },
			}
			tasks:add_at(5, task)

			eq(task, tasks:delete(sample_uid1))
		end)
	end)

	describe("add_at", function()
		it("adds one task", function()
			local tasks = ts.Tasks:new()
			---@type tasks.Task
			local task = {
				uid = sample_uid1,
				ical = stub_ical,
				vtodo = { completed = false },
			}
			tasks:add_at(1, task)
			eq({ task }, tasks:to_list())
		end)

		it("disregards sorting and puts the task at 2 instead of 1", function()
			local tasks = ts.Tasks:new({
				vtodo_comp = vtodo_comp_uncecked_first_then_summary_alpha,
			})
			---@type tasks.Task
			local task1 = {
				uid = sample_uid1,
				ical = "",
				vtodo = {
					completed = true,
					summary = "1) if sorted, would be second",
				},
			}
			local task2 = {
				uid = sample_uid2,
				ical = "",
				vtodo = {
					completed = true,
					summary = "2) if sorted, would be third",
				},
			}
			---@type tasks.Task
			local task3 = {
				uid = sample_uid3,
				ical = "",
				vtodo = {
					completed = false,
					summary = "if sorted, would be first due to completed = false",
					description = "but explicitly, should be third",
				},
			}
			tasks:add(task1.uid, task1)
			tasks:add(task2.uid, task2)
			tasks:add_at(3, task3)
			eq({ task1, task2, task3 }, tasks:to_list())
		end)

		-- it("does not add if task with given UID already exists in sorted", function ()
			-- error("TODO")
		-- end)

		-- it("does not add if task with given UID already exists in unsorted", function ()
			-- error("TODO")
		-- end)
	end)

	describe("delete_at", function()
		it("does & returns nil if no task is there", function ()
			local tasks = ts.Tasks:new()
			eq(nil, tasks:delete_at(5))
		end)

		it("deletes existing sorted task", function ()
			local tasks = ts.Tasks:new()
			---@type tasks.Task
			local task = {
				uid = sample_uid1,
				ical = stub_ical,
				vtodo = { completed = false },
			}
			tasks:add(sample_uid1, task)
			eq(task, tasks:delete_at(1))
		end)

		it("deletes existing unsorted task", function ()
			local tasks = ts.Tasks:new()
			---@type tasks.Task
			local task = {
				uid = sample_uid1,
				ical = stub_ical,
				vtodo = { completed = false },
			}
			tasks:add_at(2, task)
			eq(task, tasks:delete_at(2))
		end)
	end)

	describe("update_at", function ()
		it("updates this sorted task that happens to be at that index", function ()
			local tasks = ts.Tasks:new()
			---@type tasks.Task
			local task_before = {
				uid = sample_uid1,
				ical = stub_ical,
				vtodo = { completed = false },
			}
			tasks:add(task_before.uid, task_before)
			local task_after = {
				uid = sample_uid1,
				ical = stub_ical,
				vtodo = { completed = true },
			}
			tasks:update_at(1, task_after.vtodo)
			eq({task_after}, tasks:to_list())
		end)

		it("updates this unsorted task that is at that index", function ()
			local tasks = ts.Tasks:new()
			---@type tasks.Task
			local task_before = {
				uid = sample_uid1,
				ical = stub_ical,
				vtodo = { completed = false },
			}
			tasks:add_at(5, task_before)
			---@type tasks.Task
			local task_after = {
				uid = sample_uid1,
				ical = stub_ical,
				vtodo = { completed = true },
			}
			tasks:update_at(5, task_after.vtodo)
			eq(task_after, tasks:get_at(5))
		end)

		it("returns false if there's nothing at that index", function ()
			local tasks = ts.Tasks:new()
			eq(false, tasks:update_at(5, { completed = true }))
		end)
	end)

	describe("uids", function ()
		it("returns two UIDs for one sorted and one unsorted task", function ()
			local tasks = ts.Tasks:new()
			---@type tasks.Task
			local task1 = {
				uid = sample_uid1,
				ical = stub_ical,
				vtodo = { completed = false },
			}
			---@type tasks.Task
			local task2 = {
				uid = sample_uid2,
				ical = stub_ical,
				vtodo = { completed = false },
			}
			tasks:add(task1.uid, task1)
			tasks:add_at(1, task2)

			local expected = {sample_uid1, sample_uid2}
			table.sort(expected)
			local actual = tasks:uids()
			table.sort(actual)
			eq(expected, actual)
		end)
	end)
end)
