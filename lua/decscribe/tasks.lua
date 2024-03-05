local M = {}

---@alias tasks.VtodoComp
---| fun(a: ical.vtodo_t, b: ical.vtodo_t): boolean

---@type tasks.VtodoComp
function M.vtodo_comp_default(vtodo1, vtodo2)
	local completed1 = vtodo1.completed and 1 or 0
	local completed2 = vtodo2.completed and 1 or 0
	if completed1 ~= completed2 then return completed1 < completed2 end

	local due1 = (vtodo1.due or {}).timestamp
	local due2 = (vtodo2.due or {}).timestamp
	-- if one of the tasks does not have a due date, it defaults to anything AFTER
	-- the other:
	if not due1 and due2 then due1 = due2 + 1 end
	if due1 and not due2 then due2 = due1 + 1 end
	if due1 ~= due2 then return due1 < due2 end

	local priority1 = tonumber(vtodo1.priority) or 0
	local priority2 = tonumber(vtodo2.priority) or 0
	if priority1 ~= priority2 then return priority1 < priority2 end

	local summary1 = vtodo1.summary or ""
	local summary2 = vtodo2.summary or ""
	return summary1 < summary2
end

---@class (exact) tasks.Task
---@field private __index any
---@field uid ical.uid_t
---@field vtodo ical.vtodo_t
---@field ical ical.ical_t
local Task = {}
Task.__index = Task
M.Task = Task

---@class (exact) tasks.Tasks
---@field private sorted_tasks table<ical.uid_t, tasks.Task>
---@field private indexed_tasks table<number, tasks.Task>
---@field private vtodo_comp tasks.VtodoComp
---@field private __index any
local Tasks = {}
Tasks.__index = Tasks
M.Tasks = Tasks

---@class (exact) tasks.TasksNewParams
---@field vtodo_comp? tasks.VtodoComp

---@param params? tasks.TasksNewParams
---@return tasks.Tasks
function Tasks:new(params)
	params = params or {}
	---@type tasks.Tasks
	local obj = {
		sorted_tasks = {},
		indexed_tasks = {},
		vtodo_comp = params.vtodo_comp or M.vtodo_comp_default,
	}
	return setmetatable(obj, self)
end

---@return ical.uid_t[] uids of all tasks currently in the list
function Tasks:uids()
	local uid_set = {}
	for uid, _ in pairs(self.sorted_tasks) do
		uid_set[uid] = true
	end
	for _, task in pairs(self.indexed_tasks) do
		uid_set[task.uid] = true
	end
	local uid_list = vim.tbl_keys(uid_set)
	table.sort(uid_list)
	return uid_list
end

---@param idx integer index in the perceived list
---@return tasks.Task? task located at the given index of the sorted list
function Tasks:get_at(idx) return self:to_list()[idx] end

---@param uid ical.uid_t
---@param task tasks.Task
function Tasks:add(uid, task) self.sorted_tasks[uid] = task end

---Disregards sorting and puts the task at specifically that index. The sorting
---won't change unless the list is explicitly sorted.
---@param idx number
---@param task tasks.Task
function Tasks:add_at(idx, task) table.insert(self.indexed_tasks, idx, task) end

---@return tasks.Task? deleted_task if there was any
function Tasks:delete(uid)
	if self.sorted_tasks[uid] then
		local out = self.sorted_tasks[uid]
		self.sorted_tasks[uid] = nil
		return out
	end
	for tgt_idx, task in pairs(self.indexed_tasks) do
		if task.uid == uid then
			self.indexed_tasks[tgt_idx] = nil
			return task
		end
	end
end

---@return tasks.Task? deleted_task if there was any
function Tasks:delete_at(idx)
	local out = nil
	if self.indexed_tasks[idx] then
		out = self.indexed_tasks[idx]
		self.indexed_tasks[idx] = nil
	else
		local list = self:to_list()
		out = list[idx]
		if out then self.sorted_tasks[out.uid] = nil end
	end
	return out
end

---@param index integer at which resides the task getting updated
---@param vtodo ical.vtodo_t
---@return boolean updated whether something was updated; `false` if there was nothing at that index
function Tasks:update_at(index, vtodo)
	local idx = index
	if self.indexed_tasks[idx] then
		self.indexed_tasks[idx].vtodo = vtodo
	else
		local list = self:to_list()
		local task = list[idx]
		if task then
			self.sorted_tasks[task.uid].vtodo = vtodo
		else -- there's no task at that index - return false:
			return false
		end
	end
	return true
end

---@return tasks.Task[]
function Tasks:to_list()
	local out = vim.tbl_values(self.sorted_tasks)
	table.sort(
		out,
		function(task1, task2) return self.vtodo_comp(task1.vtodo, task2.vtodo) end
	)
	for tgt_idx, task in pairs(self.indexed_tasks) do
		table.insert(out, tgt_idx, task)
	end
	return out
end

return M
