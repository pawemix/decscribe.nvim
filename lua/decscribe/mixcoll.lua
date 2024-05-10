local M = {}

---@generic Id, Item
---@alias decscribe.mixcoll.MixColl<Id, Item> { [Id|number]: Item? }
M.MixColl = {}

---@generic Id, Item
---@param coll decscribe.mixcoll.MixColl<Id, Item>
---@param comp_fn? fun(fst: Item, snd: Item): boolean
---@return Item[]
function M.to_sorted_list(coll, comp_fn)
	comp_fn = comp_fn or function(a, b) return a < b end
	local out = {}
	---@type number[]
	local ordered_vtodo_indices = {}
	for key, vtodo in pairs(coll) do
		if type(key) == "number" then
			table.insert(ordered_vtodo_indices, key)
		elseif type(key) == "string" then
			table.insert(out, vtodo)
		else
			error("unexpected type of key in vtodo collection")
		end
	end
	table.sort(ordered_vtodo_indices)
	table.sort(out, comp_fn)
	for i = #ordered_vtodo_indices, 1, -1 do
		local ordered_vtodo_index = ordered_vtodo_indices[i]
		local ordered_vtodo = coll[ordered_vtodo_index]
		assert(ordered_vtodo)
		table.insert(out, ordered_vtodo_index, ordered_vtodo)
	end
	return out
end

---@generic Id, Item
---@param coll decscribe.mixcoll.MixColl<Id, Item>
---@param idx number
---@param comp_fn fun(fst: Item, snd: Item): boolean
---@return Item
function M.get_at(coll, idx, comp_fn)
	return coll[idx] or M.to_sorted_list(coll, comp_fn)[idx]
end

---@generic Id, Item
---@param coll decscribe.mixcoll.MixColl<Id, Item>
---@param idx number
---@param id_fn? fun(item: Item): Id
---@param comp_fn? fun(fst: Item, snd: Item): boolean
---@return Item? deleted_item_if_any
function M.delete_at(coll, idx, id_fn, comp_fn)
	local deleted = coll[idx]
	-- if there's an item EXPLICITLY at this idx:
	if deleted then
		coll[idx] = nil
		-- shift all number-indexed items AFTER THE ITEM one item closer:
		local indices_to_shift = {}
		for idx_to_shift, _ in pairs(coll) do
			if type(idx_to_shift) == "number" and idx_to_shift > idx then
				table.insert(indices_to_shift, idx_to_shift)
			end
		end
		table.sort(indices_to_shift)
		for _, idx_to_shift in ipairs(indices_to_shift) do
			coll[idx_to_shift - 1] = coll[idx_to_shift]
			coll[idx_to_shift] = nil
		end
		return deleted
	end
	-- we cannot seek the item in Id indices without a comparison fn, so we bail:
	if not comp_fn then return nil end
	--
	deleted = M.to_sorted_list(coll, comp_fn)[idx]
	if deleted and id_fn then
		coll[id_fn(deleted)] = nil
		return deleted
	end
	return nil
end

---@generic Id, Item
---@param coll decscribe.mixcoll.MixColl<Id, Item>
---@param idx number
---@param item Item
---@param id_fn? fun(item: Item): Id
---@param comp_fn? fun(fst: Item, snd: Item): boolean
---@return boolean successfully_put
function M.put_at(coll, idx, item, id_fn, comp_fn)
	if coll[idx] then
		coll[idx] = item
		return true
	end
	-- we cannot seek the item in Id indices without a comparison fn and an ID
	-- getter, so we bail:
	if not comp_fn or not id_fn then return false end
	local prev_item = M.to_sorted_list(coll, comp_fn)[idx]
	if not prev_item then return false end
	coll[id_fn(prev_item)] = item
	return true
end

function M.post_at(coll, idx, item)
	-- first, shift all explicitly indexed items after/at the given index one
	-- index forwards
	local indices_to_shift = {}
	for idx_to_shift, _ in pairs(coll) do
		if type(idx_to_shift) == "number" and idx_to_shift >= idx then
			table.insert(indices_to_shift, idx_to_shift)
		end
	end
	-- sort indices_to_shift IN REVERSE to not overwrite when shifting forwards:
	table.sort(indices_to_shift, function(a, b) return a > b end)
	for _, idx_to_shift in ipairs(indices_to_shift) do
		coll[idx_to_shift + 1] = coll[idx_to_shift]
		coll[idx_to_shift] = nil
	end
	-- finally, put the given item there:
	coll[idx] = item
end

return M
