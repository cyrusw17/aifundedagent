-- The needle index (CEO "Addiction push" H10): every needle type found plain, Wet and mutated, kept in the slot's
-- state.needleIndex (math in Shared/NeedleIndex, saved by Data). Needle.spawn calls NeedleIndex.found for every needle
-- made for a player, so finds by hand, by sorter, and needles coming back from a save all count. Each milestone in
-- Prices.NeedleIndex pays once per slot through Bank.earn ("Discovered ...", a one-time reward) and gives a title.
--
-- For the UI (index screen), on each player:
--   attribute NeedleIndexFound  "steel,steel:wet,cosmic:mutated" (entry keys, comma separated)
--   attribute NeedleIndexPercent 0..100;  NeedleIndexTitle  the highest title earned (nil before 25%)
--   attribute NeedleIndexSkin   "gilded" once 75% is reached (the gilded sorter skin)
--   NeedleIndex.entries() -> every entry key in book order; Shared/NeedleIndex.key builds one from (id, mult)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Index = require(Shared.NeedleIndex)
local Prices = require(Shared.Config.Prices)
local Data = require(script.Parent.Data)
local Bank = require(script.Parent.Bank)

local NeedleIndex = {}
local lastToast = setmetatable({}, { __mode = "k" })

local ids = {}
for id in Prices.Needles do
	table.insert(ids, id)
end
table.sort(ids, function(a, b)
	return Prices.Needles[a] < Prices.Needles[b] -- book order: cheapest type first
end)
local milestones, byAt = {}, {}
for _, r in Prices.NeedleIndex do
	table.insert(milestones, r.at)
	byAt[r.at] = r
end
table.sort(milestones)

function NeedleIndex.entries()
	return Index.entries(ids)
end

local function publish(player, index)
	local keys = {}
	for _, key in Index.entries(ids) do
		if index.found[key] then
			table.insert(keys, key)
		end
	end
	player:SetAttribute("NeedleIndexFound", table.concat(keys, ","))
	player:SetAttribute("NeedleIndexPercent", Index.percent(index, ids))
	local title, skin
	for _, m in milestones do
		if index.paid[m] then
			title = byAt[m].title or title
			skin = byAt[m].skin or skin
		end
	end
	player:SetAttribute("NeedleIndexTitle", title)
	player:SetAttribute("NeedleIndexSkin", skin)
end

-- A needle of needleId (mult: 1 plain, Prices.WetMutation.mult Wet, more mutated) was made for ownerId.
function NeedleIndex.found(ownerId, needleId, mult)
	local player = typeof(ownerId) == "number" and Players:GetPlayerByUserId(ownerId)
	local state = player and Data.get(player)
	if not state or typeof(needleId) ~= "string" or not Prices.Needles[needleId] then
		return
	end
	state.needleIndex = state.needleIndex or Index.clean(nil)
	local key = Index.key(needleId, mult, Prices.WetMutation.mult)
	local isNew, reached = Index.record(state.needleIndex, key, ids, milestones)
	if not isNew then
		return
	end
	publish(player, state.needleIndex)
	for _, m in reached do
		local r = byAt[m]
		Bank.earn(player, r.cash, ("Discovered %d%% of the needle index"):format(m))
		Data.toast(player, ("Needle index %d%%! +$%d and the title \"%s\"%s."):format(m, r.cash, r.title, r.skin and ", plus the gilded sorter skin" or ""))
	end
	-- One "new entry" toast at a time, so a bin restored from a save doesn't flood the screen.
	if #reached == 0 and os.clock() - (lastToast[player] or -math.huge) > 3 then
		lastToast[player] = os.clock()
		local have, all = Index.count(state.needleIndex, ids)
		Data.toast(player, ("New in your needle index: %s (%d of %d)."):format((key:gsub(":", " ")), have, all))
	end
end

-- Puts a loaded slot's index on the player (call after Data loads, and after a slot switch).
function NeedleIndex.load(player)
	local state = Data.get(player)
	if state then
		state.needleIndex = state.needleIndex or Index.clean(nil)
		publish(player, state.needleIndex)
	end
end

Data.loaded.Event:Connect(NeedleIndex.load)
for _, player in Players:GetPlayers() do
	task.spawn(NeedleIndex.load, player)
end

return NeedleIndex
