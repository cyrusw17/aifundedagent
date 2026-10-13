--!nonstrict
-- What each tool can do. The client only says where it clicked; the server decides what happens.
--   bare hands: lift a whole barrel
--   shovel:     smash a barrel open, or scoop a few loose pieces
--   rake:       drag loose pieces across the ground
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.Game)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Data = require(script.Parent.Data)
local Avatar = require(script.Parent.Avatar)
local Barrels = require(script.Parent.Barrels)
local Hay = require(script.Parent.Hay)

local Tools = {}

local rng = Random.new()

local function useShovel(player, root, position, target)
	local barrel = target and Barrels.fromPart(target)
	if barrel and not barrel.carriedBy then
		Avatar.swing(player, "Shovel", function()
			Barrels.breakOpen(player, barrel)
		end)
		return
	end

	local state = Data.get(player)
	if not state or #Hay.near(position, Config.ShovelRadius, 1) == 0 then
		return
	end
	if state.loadHay + Config.HayPerPiece > Config.CarryCapacity then
		Data.toast(player, "You are carrying all the hay you can. Sell it at the pad by the shop.")
		return
	end

	Avatar.swing(player, "Shovel", function()
		-- The swing takes a moment, so look again when the shovel lands and respect the carry limit.
		local room = math.floor((Config.CarryCapacity - state.loadHay) / Config.HayPerPiece)
		local list = Hay.near(position, Config.ShovelRadius, math.min(Config.ShovelPieces, room))
		if #list == 0 then
			return
		end
		local hay = #list * Config.HayPerPiece
		state.loadHay += hay
		state.loadNeedles += Economy.rollNeedles(rng, hay, Config.NeedleChancePerHay)
		Data.sync(player)
		Hay.flyToPlayer(root, list)
	end)
end

local function useRake(player, root, position)
	Avatar.swing(player, "Rake", function()
		Hay.rake(position, root.Position, Config.RakeRadius, player.UserId)
	end)
end

function Tools.init()
	local useRemote = Instance.new("RemoteEvent")
	useRemote.Name = "UseTool"
	useRemote.Parent = ReplicatedStorage
	useRemote.OnServerEvent:Connect(function(player, position, target)
		if typeof(position) ~= "Vector3" or (target ~= nil and typeof(target) ~= "Instance") then
			return
		end
		local root = Avatar.getRoot(player)
		local kind = Avatar.equippedKind(player)
		if not root or not kind or (position - root.Position).Magnitude > Config.ToolReach then
			return
		end
		if kind == "Shovel" then
			useShovel(player, root, position, target)
		elseif kind == "Rake" then
			useRake(player, root, position)
		end
	end)

	local pickupRemote = Instance.new("RemoteEvent")
	pickupRemote.Name = "PickUpBarrel"
	pickupRemote.Parent = ReplicatedStorage
	pickupRemote.OnServerEvent:Connect(function(player, body)
		if typeof(body) ~= "Instance" then
			return
		end
		local barrel = Barrels.fromPart(body)
		if barrel then
			Barrels.pickup(player, barrel)
		end
	end)

	local dropRemote = Instance.new("RemoteEvent")
	dropRemote.Name = "DropBarrel"
	dropRemote.Parent = ReplicatedStorage
	dropRemote.OnServerEvent:Connect(function(player)
		Barrels.drop(player)
	end)
end

return Tools
