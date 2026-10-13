--!nonstrict
-- The needle object. Every needle found in hay is a real physical part (tag "Needle") that stays in the world:
-- sorters throw them into bins, and anyone can click one to pick it up into their pocket. SELL NEEDLES pads pay for
-- the needles in their bin plus the ones in your pocket. Other services (sorters, spilled hay) make needles here.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Factory = require(ReplicatedStorage.Shared.Config.Factory)
local Needles = require(ReplicatedStorage.Shared.Config.Needles)
local Data = require(script.Parent.Data)
local Groups = require(script.Parent.Groups)

local Needle = {}

local SIZE = Vector3.new(1.2, 0.15, 0.15)
local COLOR = Color3.fromRGB(128, 117, 105) -- plain weathered metal
local PICKUP_REACH = 10

local types = {}
for _, n in Needles do
	types[n.id] = n
end
Needle.default = types[Factory.NeedleId] or Needles[1]

local folder = Instance.new("Folder")
folder.Name = "Needles"
folder.Parent = Workspace

local held = {} -- player -> { [needleId] = count }

function Needle.info(id)
	return types[id] or Needle.default
end

-- Needles in this player's pocket, as { [needleId] = count }.
function Needle.held(player)
	return held[player] or {}
end

-- Empties the player's pocket and returns what was in it.
function Needle.takeHeld(player)
	local pocket = held[player] or {}
	held[player] = nil
	player:SetAttribute("NeedlesHeld", 0)
	return pocket
end

local function pickUp(player, n)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not n.Parent or (n.Position - root.Position).Magnitude > PICKUP_REACH + 2 then
		return
	end
	local id = n:GetAttribute("NeedleId") or Needle.default.id
	local pocket = held[player] or {}
	pocket[id] = (pocket[id] or 0) + 1
	held[player] = pocket
	player:SetAttribute("NeedlesHeld", (player:GetAttribute("NeedlesHeld") or 0) + 1)
	n:Destroy()
	Data.toast(player, ("Picked up a %s needle. Sell it at a SELL NEEDLES pad."):format(Needle.info(id).name:lower()))
end

-- Makes a needle at position. ownerId is who it belongs to while it sits in a bin.
function Needle.spawn(position, ownerId, needleId)
	local n = Instance.new("Part")
	n.Name = "Needle"
	n.Shape = Enum.PartType.Cylinder
	n.Size = SIZE
	n.CFrame = CFrame.new(position)
	n.Color = COLOR
	n.Material = Enum.Material.Metal
	n.CollisionGroup = Groups.Loose
	n:SetAttribute("OwnerId", ownerId)
	n:SetAttribute("NeedleId", needleId or Needle.default.id)
	CollectionService:AddTag(n, "Needle")

	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = PICKUP_REACH
	click.MouseClick:Connect(function(player)
		pickUp(player, n)
	end)
	click.Parent = n

	n.Parent = folder
	pcall(function()
		n:SetNetworkOwner(nil)
	end)
	return n
end

-- Throws a needle in an arc from `from` to land at `to`, then lets it settle with physics.
function Needle.throw(from, to, ownerId, needleId)
	local n = Needle.spawn(from, ownerId, needleId)
	n.Anchored = true
	n.CanCollide = false
	task.spawn(function()
		local started = os.clock()
		local control = (from + to) / 2 + Vector3.new(0, 4, 0)
		while n.Parent do
			local alpha = math.min((os.clock() - started) / 0.6, 1)
			local inv = 1 - alpha
			n.CFrame = CFrame.new(inv * inv * from + 2 * inv * alpha * control + alpha * alpha * to)
				* CFrame.Angles(alpha * 9, alpha * 5, 0)
			if alpha >= 1 then
				break
			end
			RunService.Heartbeat:Wait()
		end
		if n.Parent then
			n.Anchored = false
			n.CanCollide = true
			pcall(function()
				n:SetNetworkOwner(nil)
			end)
		end
	end)
	return n
end

-- Needle parts inside a box.
function Needle.inBox(cframe, size)
	local found = {}
	for _, p in Workspace:GetPartBoundsInBox(cframe, size) do
		if CollectionService:HasTag(p, "Needle") then
			table.insert(found, p)
		end
	end
	return found
end

Players.PlayerRemoving:Connect(function(player)
	held[player] = nil
end)

return Needle
