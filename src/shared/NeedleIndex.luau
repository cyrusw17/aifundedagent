--!strict
-- The needle index (CEO "Addiction push" H10): every needle type in each kind (plain, Wet, mutated) a player has
-- found, and the completion rewards already paid. Pure, so tests/needle_index.luau and the save check
-- (tools/linecheck/saves.luau) run it headlessly; Services/NeedleIndex records finds and pays.
--
--   index = { found = { [entryKey] = true }, paid = { [milestone] = true } }   (saved with the slot)
--   NeedleIndex.key(needleId, mult, wetMult) -> "steel", "steel:wet" or "steel:mutated"
--   NeedleIndex.entries(needleIds)           -> every entry key, in book order (type, then kind)
--   NeedleIndex.record(index, key, needleIds, milestones) -> isNew, { milestones newly reached }
--   NeedleIndex.percent(index, needleIds)    -> 0..100, whole
--   NeedleIndex.clean(saved)                 -> a fresh index from a save, odd values dropped
local NeedleIndex = {}

NeedleIndex.KINDS = { "plain", "wet", "mutated" }
local MAX_KEYS = 400

function NeedleIndex.key(needleId: string, mult: number?, wetMult: number?): string
	local m = mult or 1
	if m == wetMult then
		return needleId .. ":wet"
	elseif m > 1 then
		return needleId .. ":mutated"
	end
	return needleId
end

function NeedleIndex.entries(needleIds: { string }): { string }
	local out = {}
	for _, id in needleIds do
		table.insert(out, id)
		table.insert(out, id .. ":wet")
		table.insert(out, id .. ":mutated")
	end
	return out
end

function NeedleIndex.count(index, needleIds: { string }): (number, number)
	local have, all = 0, 0
	for _, key in NeedleIndex.entries(needleIds) do
		all += 1
		if index.found[key] then
			have += 1
		end
	end
	return have, all
end

function NeedleIndex.percent(index, needleIds: { string }): number
	local have, all = NeedleIndex.count(index, needleIds)
	return if all == 0 then 0 else math.floor(have / all * 100)
end

-- Marks key found. Returns whether it was new, and the milestones (sorted, from `milestones`) it newly reaches,
-- which it marks paid: each one is reached once per slot, whatever happens after.
function NeedleIndex.record(index, key: string, needleIds: { string }, milestones: { number }): (boolean, { number })
	local reached = {}
	if index.found[key] then
		return false, reached
	end
	index.found[key] = true
	local pct = NeedleIndex.percent(index, needleIds)
	for _, m in milestones do
		if pct >= m and not index.paid[m] then
			index.paid[m] = true
			table.insert(reached, m)
		end
	end
	table.sort(reached)
	return true, reached
end

local function validKey(key: any): boolean
	return typeof(key) == "string"
		and #key <= 40
		and (key:match("^%w+$") or key:match("^%w+:wet$") or key:match("^%w+:mutated$")) ~= nil
end

function NeedleIndex.clean(saved: any)
	local index = { found = {}, paid = {} }
	if typeof(saved) ~= "table" then
		return index
	end
	local n = 0
	if typeof(saved.found) == "table" then
		for key, v in saved.found do
			if v == true and n < MAX_KEYS and validKey(key) then
				index.found[key] = true
				n += 1
			end
		end
	end
	if typeof(saved.paid) == "table" then
		for m, v in saved.paid do
			local num = tonumber(m)
			if v == true and num and num == math.floor(num) and num >= 1 and num <= 100 then
				index.paid[num] = true
			end
		end
	end
	return index
end

-- For a save: string keys only (a DataStore drops number-keyed tables with gaps), so paid becomes { ["25"] = true }.
function NeedleIndex.toSave(index)
	local paid = {}
	for m in index.paid do
		paid[tostring(m)] = true
	end
	return { found = table.clone(index.found), paid = paid }
end

return NeedleIndex
