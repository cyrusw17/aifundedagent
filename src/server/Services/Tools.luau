--!nonstrict
-- What each tool does when you click with it. The click itself comes from the tool's server-side Activated
-- signal. The client also reports where the click pointed (ToolAim), so a tool works on the exact hay piece or
-- bale you clicked. If no aim arrives, the tool works on what is in front of you.
--   shovel: smash the clicked bale, or scoop the clicked hay piece and the pieces next to it
--   rake:   drag the loose pieces around the click back toward you, spreading them across the ground
-- Bare hands lift a whole bale with its Pick up button (see Bales.luau).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config.Game)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Data = require(script.Parent.Data)
local Avatar = require(script.Parent.Avatar)
local Bales = require(script.Parent.Bales)
local Hay = require(script.Parent.Hay)
local Gloves = require(script.Parent.Gloves)
local Events = require(script.Parent.Events)
local Feedback = require(script.Parent.Feedback)

local Tools = {}

local rng = Random.new()
local aims = {} -- player -> { position, part, time } from the latest click

local AIM_FRESH = 0.4 -- seconds an aim counts as belonging to the current click
local AIM_WAIT = 0.15 -- how long a click waits for its aim to arrive

-- The spot on the ground a little in front of the player.
local function spotInFront(root, distance)
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then
		flat = Vector3.new(0, 0, -1)
	end
	return root.Position + flat.Unit * distance - Vector3.new(0, 2, 0)
end

-- The aim for this click if the client sent one in reach, waiting briefly since it may land just after the click.
local function currentAim(player, root)
	local started = os.clock()
	while true do
		local aim = aims[player]
		if aim and os.clock() - aim.time < AIM_FRESH then
			aims[player] = nil
			if (aim.position - root.Position).Magnitude <= Config.ToolReach then
				return aim
			end
			return nil
		end
		if os.clock() - started > AIM_WAIT then
			return nil
		end
		task.wait()
	end
end

local function useShovel(player, root, aim)
	local bale
	if aim then
		bale = aim.part and Bales.fromPart(aim.part)
	else
		bale = Bales.inFront(root, Config.ShovelReach)
	end
	if bale and not bale.carriedBy then
		Avatar.swing(player, "Shovel", function()
			Bales.breakOpen(player, bale)
		end)
		return
	end

	local state = Data.get(player)
	if not state then
		return
	end
	-- The clicked spot, or else the ground in front of you. Pieces right at your feet count too.
	local function targetPieces(max)
		local center = aim and aim.position or spotInFront(root, Config.ShovelReach / 2)
		local list = Hay.near(center, Config.ShovelRadius, max)
		if #list == 0 and not aim then
			list = Hay.near(root.Position - Vector3.new(0, 2.5, 0), Config.ShovelRadius, max)
		end
		return list
	end

	if #targetPieces(1) == 0 then
		Data.toast(player, "No hay there. Click a bale or a hay piece.")
		return
	end
	local capacity = Gloves.carryCapacity(player)
	if state.loadHay + Config.HayPerPiece > capacity then
		Data.toast(player, "You are carrying all the hay you can. Sell it at the pad by the shop.")
		return
	end

	Avatar.swing(player, "Shovel", function()
		-- The swing takes a moment, so look again when the shovel lands and respect the carry limit.
		-- Better gloves scoop more; hay rarer than your gloves are rated for scoops less.
		local room = math.floor((capacity - state.loadHay) / Config.HayPerPiece)
		local first = targetPieces(1)[1]
		local _, hayTier = if first then Gloves.pieceWeight(first) else 0, 0
		local list = targetPieces(math.min(Gloves.scoopSize(player, hayTier), room))
		if #list == 0 then
			return
		end
		local strands, found = 0, 0
		for i = #list, 1, -1 do
			local piece = list[i]
			if Hay.isNeedle(piece) then
				if Hay.sharedNeedles then
					table.remove(list, i) -- a shared needle is picked up by clicking it, so the shovel leaves it
				else
					found += 1
				end
			else
				strands += 1
				local weight, tier = Gloves.pieceWeight(piece)
				state.loadWeight = (state.loadWeight or 0) + weight
				state.loadTier = math.max(state.loadTier or 0, tier)
			end
		end
		local hay = strands * Config.HayPerPiece
		state.loadHay += hay
		state.loadNeedles += found + Economy.rollNeedles(rng, hay, Config.NeedleChancePerHay)
		Data.sync(player)
		Hay.flyToPlayer(root, list)
		Feedback.play("Scoop", root)
		if found > 0 then
			Feedback.needle(root)
			Data.toast(player, found == 1 and "You found a needle in the hay!" or ("You found %d needles!"):format(found))
		end
	end)
end

local function useRake(player, root, aim)
	local center = aim and aim.position or spotInFront(root, Config.RakeRadius)
	Avatar.swing(player, "Rake", function()
		-- Gather toward the ground a couple of studs in front of the player, on the side the hay is on.
		local flat = Vector3.new(center.X - root.Position.X, 0, center.Z - root.Position.Z)
		local dir = flat.Magnitude > 0.1 and flat.Unit or Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
		local gatherAt = root.Position + dir * Config.RakeGatherDistance
		Hay.rake(center, gatherAt, Config.RakeRadius, player.UserId)
		Events.fire(player, "raked", 1, { center = center })
		Feedback.play("Rake", center)
	end)
end

function Tools.init()
	Feedback.init()
	Gloves.init()
	-- The glove stand goes beside the sell pad once the world has built it.
	task.defer(function()
		local world = workspace:FindFirstChild("Needlewood")
		local pad = world and world:WaitForChild("SellPad", 10)
		if pad then
			Gloves.buildStand(world, CFrame.new(pad.Position.X - pad.Size.X / 2 - 3.5, 0, pad.Position.Z))
		end
	end)

	local aimRemote = Instance.new("RemoteEvent")
	aimRemote.Name = "ToolAim"
	aimRemote.Parent = ReplicatedStorage
	aimRemote.OnServerEvent:Connect(function(player, position, part)
		if typeof(position) ~= "Vector3" or (part ~= nil and typeof(part) ~= "Instance") then
			return
		end
		aims[player] = { position = position, part = part, time = os.clock() }
	end)
	Players.PlayerRemoving:Connect(function(player)
		aims[player] = nil
	end)

	Avatar.onToolActivated = function(player, kind)
		local root = Avatar.getRoot(player)
		local state = Data.get(player)
		if not root or not state or state.carryBale then
			return
		end
		local aim = currentAim(player, root)
		if kind == "Shovel" then
			useShovel(player, root, aim)
		elseif kind == "Rake" then
			useRake(player, root, aim)
		end
	end

	-- Putting a carried bale down from the keyboard (G) or a click. The bale's own button does the same.
	local dropRemote = Instance.new("RemoteEvent")
	dropRemote.Name = "DropBale"
	dropRemote.Parent = ReplicatedStorage
	dropRemote.OnServerEvent:Connect(function(player)
		Bales.drop(player)
	end)
end

return Tools
