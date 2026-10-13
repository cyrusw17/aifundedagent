--!nonstrict
-- Rebirth (CEO H5, Prices.Rebirth). Once a slot owns the Semi it can start the climb again: cash, the bank and its
-- loans, trucks, trailers, everything built on the farm, plot upgrades, the second farm and plain needles reset, and
-- every sale after it pays Prices.Rebirth.Bonus more per rebirth for good (Bank.earn reads state.rebirth.count), up to
-- Prices.Rebirth.Max. Kept: the plot itself, shovels and gear, the needle index, cosmetics and skins, finds, mutated
-- needles, quests, the codex (best needle), settings, blueprints and the tutorial.
--
-- The world (trucks out, the farm's machines) is built from the save when a slot loads, so a rebirth saves the reset
-- slot and sends the player back through a rejoin (TeleportService to this place; a kick with a message if that
-- fails, as in Studio).
--
--   Rebirth.check(state)  -> ok, why: whether this slot can rebirth now
--   Rebirth.reset(state)  -> the reset applied to a state table in place (SelfTests/Economy runs it on a copy)
--   Rebirth.go(player)    -> ok, message
-- Remote: ReplicatedStorage.Rebirth (RemoteFunction, no arguments) -> ok, message. Player attributes: RebirthCount,
-- RebirthReady (true when check passes), RebirthBonus (the sale multiplier, 1 to 1.5).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Prices = require(Shared.Config.Prices)
local LineMath = require(Shared.LineMath)
local RateLimit = require(Shared.RateLimit)
local Data = require(script.Parent.Data)
local Bank = require(script.Parent.Bank)

local Rebirth = {}

local Terms = Prices.Rebirth

local function countOf(state)
	local r = state.rebirth
	return typeof(r) == "table" and typeof(r.count) == "number" and math.clamp(math.floor(r.count), 0, Terms.Max) or 0
end
Rebirth.countOf = countOf

-- The sale multiplier for this many rebirths.
function Rebirth.bonus(count)
	return 1 + Terms.Bonus * math.clamp(count or 0, 0, Terms.Max)
end

function Rebirth.check(state)
	if not state then
		return false, "Pick a save first."
	end
	if countOf(state) >= Terms.Max then
		return false, ("You've reached the last rebirth (%d)."):format(Terms.Max)
	end
	if not table.find(state.trucks or {}, Terms.Unlock) then
		return false, "Rebirth opens once you own the Semi."
	end
	for _, loan in Bank.account(state).loans do
		if loan and (loan.owed or 0) > 0 then
			return false, "Pay off your loans first."
		end
	end
	return true, nil
end

-- Mutated needles stay (trophies); plain ones are money, so they reset with the cash.
local function keepMutated(counts)
	local out = {}
	for key, n in counts or {} do
		local _, mult = LineMath.parseKey(key)
		if mult and mult > 1 and n > 0 then
			out[key] = n
		end
	end
	return out
end

function Rebirth.reset(state)
	local a = Bank.account(state)
	local count = countOf(state) + 1
	state.cash = 0
	state.savedCash = 0
	a.balance = 0
	a.held = nil
	a.loans = {}
	-- Lifetime sales stay (the trade gate, the alt-account rules); daily contracts read sales since this rebirth.
	state.rebirth = { count = count, at = os.time(), soldAt = a.sold }
	state.trucks = {}
	state.trailers = {}
	state.pocket = keepMutated(state.pocket)
	if state.land then
		state.land.items = {}
		state.land.needles = keepMutated(state.land.needles)
		state.land.expansions = nil
		state.land.binSorted = nil
		state.land.binPolisher = nil
	end
	state.land2 = nil
	state.contracts = nil
	return count
end

function Rebirth.go(player)
	local state = Data.get(player)
	local ok, why = Rebirth.check(state)
	if not state or not ok then
		return false, why
	end
	local count = Rebirth.reset(state)
	Bank.record(state, "rebirth", 0, ("Rebirth %d: every sale pays %d%% more"):format(count, math.floor((Rebirth.bonus(count) - 1) * 100 + 0.5)))
	state.skipBeforeSave = true
	Data.release(player) -- a final save of the reset slot, then this server lets it go
	task.spawn(function()
		local sent = pcall(function()
			TeleportService:TeleportAsync(game.PlaceId, { player })
		end)
		if not sent and player.Parent then
			player:Kick(("Rebirth %d done! Rejoin and pick your save to start the climb again."):format(count))
		end
	end)
	return true, ("Rebirth %d! Rejoining..."):format(count)
end

local function publish(player)
	local state = Data.get(player)
	if not state then
		return
	end
	player:SetAttribute("RebirthCount", countOf(state))
	player:SetAttribute("RebirthBonus", Rebirth.bonus(countOf(state)))
	player:SetAttribute("RebirthReady", (Rebirth.check(state)))
end

function Rebirth.start()
	local remote = Instance.new("RemoteFunction")
	remote.Name = "Rebirth"
	remote.Parent = ReplicatedStorage
	local limit = RateLimit.new("Rebirth", 0.2, 1)
	remote.OnServerInvoke = function(player)
		if not limit:allow(player) then
			return false, RateLimit.BUSY
		end
		local ok, result, message = pcall(Rebirth.go, player)
		if not ok then
			warn("[Needlewood] rebirth failed: " .. tostring(result))
			return false, "Something went wrong with the rebirth. Rejoin and check your save."
		end
		return result, message
	end
	Data.loaded.Event:Connect(publish)
	task.spawn(function()
		while true do
			task.wait(5) -- buying the Semi or paying off a loan turns RebirthReady on
			for _, player in Players:GetPlayers() do
				publish(player)
			end
		end
	end)
end

return Rebirth
