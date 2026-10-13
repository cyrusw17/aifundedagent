--!nonstrict
-- The sell pad by the hay shop. Step on it with hay, set a whole barrel on it, or rake loose hay onto it.
-- No buttons or prompts. Every sale is decided here, never on the client.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config.Game)
local Economy = require(Shared.Economy)
local Data = require(script.Parent.Data)
local Barrels = require(script.Parent.Barrels)
local Hay = require(script.Parent.Hay)

local Gameplay = {}

local rng = Random.new()
local lastHaySale = {}

local function sellHay(player)
	local state = Data.get(player)
	if not state or state.loadHay <= 0 then
		return
	end
	if os.clock() - (lastHaySale[player] or 0) < 1 then
		return
	end
	lastHaySale[player] = os.clock()

	local hay, needles = state.loadHay, state.loadNeedles
	local value = Economy.rawLoadValue(hay, needles)
	state.cash += value
	state.loadHay = 0
	state.loadNeedles = 0
	Data.sync(player)
	Data.toast(
		player,
		("Sold %d hay for $%d. The shop found %d needles in it and paid $1 each."):format(hay, value, needles)
	)
end

local function sellBarrel(b)
	if b.gone or b.carriedBy or b.breaking then
		return
	end
	local hay = Config.PiecesPerBarrel * Config.HayPerPiece
	local needles = Economy.rollNeedles(rng, hay, Config.NeedleChancePerHay)
	local value = Economy.rawLoadValue(hay, needles)
	local owner = b.ownerId and Players:GetPlayerByUserId(b.ownerId)
	Barrels.consume(b)

	local state = owner and Data.get(owner)
	if state then
		state.cash += value
		Data.sync(owner)
		Data.toast(
			owner,
			("Sold a barrel: %d hay for $%d. The shop found %d needles and paid $1 each."):format(hay, value, needles)
		)
	end
end

-- Loose hay on the pad is paid to whoever last scooped, raked or smashed it.
local function sellPieces(pieces)
	local byOwner = {}
	for _, piece in pieces do
		local ownerId = piece:GetAttribute("OwnerId")
		byOwner[ownerId] = (byOwner[ownerId] or 0) + 1
		Hay.remove(piece)
	end
	for ownerId, n in byOwner do
		local owner = ownerId and Players:GetPlayerByUserId(ownerId)
		local state = owner and Data.get(owner)
		if state then
			local hay = n * Config.HayPerPiece
			local needles = Economy.rollNeedles(rng, hay, Config.NeedleChancePerHay)
			local value = Economy.rawLoadValue(hay, needles)
			state.cash += value
			Data.sync(owner)
			Data.toast(owner, ("Sold %d loose hay for $%d. The shop found %d needles."):format(hay, value, needles))
		end
	end
end

function Gameplay.wireSellPad(pad)
	task.spawn(function()
		while pad.Parent do
			task.wait(0.25)
			local box = pad.CFrame * CFrame.new(0, 3.5, 0)
			local parts = Workspace:GetPartBoundsInBox(box, Vector3.new(pad.Size.X, 7, pad.Size.Z))
			local doneBarrels, donePlayers, loose = {}, {}, {}
			for _, part in parts do
				if Hay.isPiece(part) then
					table.insert(loose, part)
				end
				local barrel = Barrels.fromPart(part)
				if barrel and not doneBarrels[barrel] then
					doneBarrels[barrel] = true
					sellBarrel(barrel)
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
