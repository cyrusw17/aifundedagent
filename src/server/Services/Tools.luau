--!nonstrict
-- What each tool does when you click with it. Everything runs on the server from the tool's own Activated
-- signal, so a click works no matter what the client scripts do. The target is whatever is in front of you.
--   shovel: smash the barrel in front of you, or scoop a few loose pieces in front of you
--   rake:   drag the loose pieces in front of you back toward you, spreading them across the ground
-- Bare hands lift a whole barrel with its Pick up prompt (see Barrels.luau).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.Game)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Data = require(script.Parent.Data)
local Avatar = require(script.Parent.Avatar)
local Barrels = require(script.Parent.Barrels)
local Hay = require(script.Parent.Hay)

local Tools = {}

local rng = Random.new()

-- The spot on the ground a little in front of the player.
local function spotInFront(root, distance)
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then
		flat = Vector3.new(0, 0, -1)
	end
	return root.Position + flat.Unit * distance - Vector3.new(0, 2, 0)
end

local function useShovel(player, root)
	local barrel = Barrels.inFront(root, Config.ShovelReach)
	if barrel then
		Avatar.swing(player, "Shovel", function()
			Barrels.breakOpen(player, barrel)
		end)
		return
	end

	local state = Data.get(player)
	local spot = spotInFront(root, Config.ShovelReach / 2)
	if not state then
		return
	end
	if #Hay.near(spot, Config.ShovelRadius, 1) == 0 then
		Data.toast(player, "Nothing to scoop here. Face a barrel or a pile of hay and click.")
		return
	end
	if state.loadHay + Config.HayPerPiece > Config.CarryCapacity then
		Data.toast(player, "You are carrying all the hay you can. Sell it at the pad by the shop.")
		return
	end

	Avatar.swing(player, "Shovel", function()
		-- The swing takes a moment, so look again when the shovel lands and respect the carry limit.
		local landed = spotInFront(root, Config.ShovelReach / 2)
		local room = math.floor((Config.CarryCapacity - state.loadHay) / Config.HayPerPiece)
		local list = Hay.near(landed, Config.ShovelRadius, math.min(Config.ShovelPieces, room))
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

local function useRake(player, root)
	Avatar.swing(player, "Rake", function()
		Hay.rake(spotInFront(root, Config.RakeRadius), root.Position, Config.RakeRadius, player.UserId)
	end)
end

function Tools.init()
	Avatar.onToolActivated = function(player, kind)
		local root = Avatar.getRoot(player)
		if not root or (Data.get(player) and Data.get(player).carryBarrel) then
			return
		end
		if kind == "Shovel" then
			useShovel(player, root)
		elseif kind == "Rake" then
			useRake(player, root)
		end
	end

	-- Putting a carried barrel down from the keyboard (G) or a click. The barrel's own prompt does the same.
	local dropRemote = Instance.new("RemoteEvent")
	dropRemote.Name = "DropBarrel"
	dropRemote.Parent = ReplicatedStorage
	dropRemote.OnServerEvent:Connect(function(player)
		Barrels.drop(player)
	end)
end

return Tools
