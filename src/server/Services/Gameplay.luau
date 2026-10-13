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
local Prices = require(Shared.Config.Prices)
local Data = require(script.Parent.Data)
local Bank = require(script.Parent.Bank)
local Bales = require(script.Parent.Bales)
local Hay = require(script.Parent.Hay)
local Feedback = require(script.Parent.Feedback)
-- The shared needle (from the conveyor work) when present: needles clicked up into a pocket sell here too.
local NeedleModule = script.Parent:FindFirstChild("Needle")
local Needle = NeedleModule and require(NeedleModule)

local Gameplay = {}

local rng = Random.new()
local lastHaySale = {}

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
	local value = hay > 0 and Economy.rawLoadValue(hay, needles) or 0
	state.loadHay = 0
	state.loadNeedles = 0

	local pocketCount, pocketValue = 0, 0
	if hasPocketNeedles(player) then
		local count, full = Needle.sellHeld(player)
		pocketCount = count
		pocketValue = math.floor(full * Prices.HandFoundNeedleShare)
	end
	value += pocketValue
	Bank.earn(player, value, "Hay shop")
	Feedback.sale(player, value)

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
	local hay = Config.PiecesPerBale * Config.HayPerPiece
	local needles = Economy.rollNeedles(rng, hay, Config.NeedleChancePerHay)
	local value = Economy.rawLoadValue(hay, needles)
	local owner = b.ownerId and Players:GetPlayerByUserId(b.ownerId)
	Bales.consume(b)

	local state = owner and Data.get(owner)
	if state then
		Bank.earn(owner, value, "Hay shop")
		Feedback.sale(owner, value)
		Data.toast(owner, ("+$%d · a bale"):format(value))
	end
end

-- Loose hay on the pad is paid to whoever last scooped, raked or smashed it.
local function sellPieces(pieces)
	local byOwner, needlesByOwner = {}, {}
	for _, piece in pieces do
		local ownerId = piece:GetAttribute("OwnerId")
		if Hay.isNeedle(piece) then
			needlesByOwner[ownerId] = (needlesByOwner[ownerId] or 0)
				+ math.floor(Hay.needleValue(piece) * Prices.HandFoundNeedleShare)
			byOwner[ownerId] = byOwner[ownerId] or 0
		else
			byOwner[ownerId] = (byOwner[ownerId] or 0) + 1
		end
		Hay.remove(piece)
	end
	for ownerId, n in byOwner do
		local owner = ownerId and Players:GetPlayerByUserId(ownerId)
		local state = owner and Data.get(owner)
		if state then
			local hay = n * Config.HayPerPiece
			-- Hidden needles in loose hay pay the raw price; needles lying in plain sight pay their full value.
			local needles = Economy.rollNeedles(rng, hay, Config.NeedleChancePerHay)
			local value = Economy.rawLoadValue(hay, needles) + (needlesByOwner[ownerId] or 0)
			Bank.earn(owner, value, "Hay shop")
			Feedback.sale(owner, value)
			Data.toast(owner, ("+$%d · %d loose hay"):format(value, hay))
		end
	end
end

function Gameplay.wireSellPad(pad)
	task.spawn(function()
		while pad.Parent do
			task.wait(0.25)
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
	end)
end

return Gameplay
