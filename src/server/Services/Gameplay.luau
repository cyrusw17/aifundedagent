--!nonstrict
-- The sell pad by the hay shop. Step on it with hay, set a whole bale on it, or rake loose hay onto it.
-- No buttons or prompts. Every sale is decided here, never on the client. Needles in your pocket sell here too,
-- at Prices.HandFoundNeedleShare of their full value, so a new player is never stuck holding one.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config.Game)
local Economy = require(Shared.Economy)
local HayMath = require(ReplicatedStorage.Shared.HayMath)
local Prices = require(Shared.Config.Prices)
local Data = require(script.Parent.Data)
local Bank = require(script.Parent.Bank)
local Bales = require(script.Parent.Bales)
local Hay = require(script.Parent.Hay)
local Feedback = require(script.Parent.Feedback)
-- The shared needle (from the conveyor work) when present: needles clicked up into a pocket sell here too.
local NeedleModule = script.Parent:FindFirstChild("Needle")
local Needle = NeedleModule and require(NeedleModule)
local Tutorial = require(script.Parent.Tutorial)
local Events = require(script.Parent.Events)

local Gameplay = {}

local rng = Random.new()
local lastHaySale = {}
Players.PlayerRemoving:Connect(function(player)
	lastHaySale[player] = nil
end)

-- What rain costs: wet hay sells at Config.WetPriceFactor of the hay price (the needles in it are unharmed).
local function wetPenalty(wetHay)
	return HayMath.wetPenalty(wetHay, Economy.HAY_PRICE, Config.WetPriceFactor)
end

local function hasPocketNeedles(player)
	return Needle ~= nil and Needle.heldCount(player) > 0
end

local function sellHay(player)
	local state = Data.get(player)
	if not state or (state.loadHay <= 0 and not hasPocketNeedles(player)) then
		return
	end
	if os.clock() - (lastHaySale[player] or 0) < 1 then
		return
	end
	lastHaySale[player] = os.clock()

	local hay, needles = state.loadHay, state.loadNeedles
	local value = hay > 0 and Economy.rawLoadValue(hay, needles) - wetPenalty(math.min(state.loadWetHay or 0, hay)) or 0
	if hay > 0 then
		Events.fire(player, "hay_sold", hay)
	end
	state.loadHay = 0
	state.loadNeedles = 0
	state.loadSortedHay = 0
	state.loadWetHay = 0
	state.loadType = nil

	local pocketCount, pocketValue = 0, 0
	if hasPocketNeedles(player) then
		local count, full = Needle.sellHeld(player)
		pocketCount = count
		pocketValue = math.floor(full * Prices.HandFoundNeedleShare)
	end
	value += pocketValue
	Bank.earn(player, value, "Hay shop")
	Feedback.sale(player, value)
	Tutorial.mark(player, "sold")
	Tutorial.earned(player, value)

	local parts = {}
	if hay > 0 then
		table.insert(parts, ("%d hay"):format(hay))
	end
	if pocketCount > 0 then
		table.insert(parts, pocketCount == 1 and "1 needle" or ("%d needles"):format(pocketCount))
	end
	Data.toast(player, ("+$%d · %s"):format(value, table.concat(parts, ", ")))
end

local function sellBale(b)
	if b.gone or b.carriedBy or b.breaking then
		return
	end
	local hay = b.sortedHay or Config.PiecesPerBale * Config.HayPerPiece
	-- A sorted bale's needles were already taken out (and paid for) by the sorter.
	local needles = if b.sorted then 0 else Economy.rollNeedles(rng, hay, Hay.needleChanceOf(b.body))
	local value = Economy.rawLoadValue(hay, needles)
	if b.body:GetAttribute("Wet") then
		value -= wetPenalty(hay)
	end
	local owner = b.ownerId and Players:GetPlayerByUserId(b.ownerId)
	local hayType = b.body:GetAttribute("HayType")
	Bales.consume(b)
	if owner then
		Events.fire(owner, "bale_sold", 1, { hayType = hayType })
	end

	local state = owner and Data.get(owner)
	if state then
		Bank.earn(owner, value, "Hay shop")
		Feedback.sale(owner, value)
		Tutorial.mark(owner, "sold")
		Tutorial.earned(owner, value)
		Data.toast(owner, ("+$%d · a bale"):format(value))
	end
end

-- Loose hay on the pad is paid to whoever last scooped, raked or smashed it.
local function sellPieces(pieces)
	local byOwner, hiddenByOwner, needlesByOwner, wetByOwner = {}, {}, {}, {}
	for _, piece in pieces do
		local ownerId = piece:GetAttribute("OwnerId")
		if Hay.isNeedle(piece) then
			needlesByOwner[ownerId] = (needlesByOwner[ownerId] or 0)
				+ math.floor(Hay.needleValue(piece) * Prices.HandFoundNeedleShare)
			byOwner[ownerId] = byOwner[ownerId] or 0
		else
			local n = Hay.strandsIn(piece) -- a raked pile counts as all the strands in it
			byOwner[ownerId] = (byOwner[ownerId] or 0) + n
			if not piece:GetAttribute("Sorted") then
				-- Hidden needles at this piece's own chance (its hay type and boosts).
				hiddenByOwner[ownerId] = (hiddenByOwner[ownerId] or 0)
					+ Economy.rollNeedles(rng, n * Config.HayPerPiece, Hay.needleChanceOf(piece))
			end
			if piece:GetAttribute("Wet") then
				wetByOwner[ownerId] = (wetByOwner[ownerId] or 0) + n
			end
		end
		Hay.remove(piece)
	end
	for ownerId, n in byOwner do
		local owner = ownerId and Players:GetPlayerByUserId(ownerId)
		local state = owner and Data.get(owner)
		if state then
			local hay = n * Config.HayPerPiece
			-- Hidden needles in loose hay pay the raw price; needles lying in plain sight pay their full value. Hay
			-- from a sorted bale has no hidden needles left.
			local needles = hiddenByOwner[ownerId] or 0
			local value = Economy.rawLoadValue(hay, needles)
				+ (needlesByOwner[ownerId] or 0)
				- wetPenalty((wetByOwner[ownerId] or 0) * Config.HayPerPiece)
			Bank.earn(owner, value, "Hay shop")
			Feedback.sale(owner, value)
			Data.toast(owner, ("+$%d · %d loose hay"):format(value, hay))
			Events.fire(owner, "hay_sold", hay)
		end
	end
end

-- One look at what is on the pad, selling it all.
local function sweepPad(pad)
	local box = pad.CFrame * CFrame.new(0, 3.5, 0)
	local parts = Workspace:GetPartBoundsInBox(box, Vector3.new(pad.Size.X, 7, pad.Size.Z))
	local doneBales, donePlayers, loose = {}, {}, {}
	for _, part in parts do
		if Hay.isPiece(part) then
			table.insert(loose, part)
		end
		local bale = Bales.fromPart(part)
		if bale and not doneBales[bale] then
			doneBales[bale] = true
			sellBale(bale)
		end
		local player = part.Parent and Players:GetPlayerFromCharacter(part.Parent)
		if player and not donePlayers[player] then
			donePlayers[player] = true
			sellHay(player)
		end
	end
	if #loose > 0 then
		sellPieces(loose)
	end
end

function Gameplay.wireSellPad(pad)
	task.spawn(function()
		while pad.Parent do
			task.wait(0.25)
			-- One bad sale must not stop the pad for the rest of the server's life.
			local ok, err = pcall(sweepPad, pad)
			if not ok then
				warn("[Needlewood] sell pad: " .. tostring(err))
			end
		end
	end)
end

return Gameplay
