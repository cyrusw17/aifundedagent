--!nonstrict
-- The needle object. Every needle found in hay is a real physical part (tag "Needle") that stays in the world:
-- sorters throw them into bins, and anyone can click one to pick it up into their pocket. SELL NEEDLES pads pay for
-- the needles in their bin plus the ones in your pocket. Other services (sorters, spilled hay) make needles here.
--
-- Each needle type has its own color (rarer types glow). About 1 in 500 found needles is MUTATED: bigger, glowing,
-- worth 3x to 25x, and announced to the whole server.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Factory = require(ReplicatedStorage.Shared.Config.Factory)
local Needles = require(ReplicatedStorage.Shared.Config.Needles)
local Data = require(script.Parent.Data)
local Groups = require(script.Parent.Groups)

local Needle = {}

local SIZE = Vector3.new(1.2, 0.15, 0.15)
local PICKUP_REACH = 10
local MUTATION_CHANCE = 1 / 500
local MUTATION_MIN, MUTATION_MAX = 3, 25
local DING = "rbxasset://sounds/electronicpingshort.wav"
local FANFARE = "rbxasset://sounds/victory.wav"

-- Color per needle type, and whether it glows. Common types are plain metal; the rare maps glow.
local LOOKS = {
	steel = { Color3.fromRGB(150, 158, 166), false },
	pine = { Color3.fromRGB(96, 140, 84), false },
	sand = { Color3.fromRGB(214, 186, 120), false },
	ice = { Color3.fromRGB(170, 220, 240), true },
	bog = { Color3.fromRGB(110, 128, 70), false },
	obsidian = { Color3.fromRGB(60, 40, 70), true },
	geode = { Color3.fromRGB(170, 110, 220), true },
	cloud = { Color3.fromRGB(240, 244, 255), true },
	phantom = { Color3.fromRGB(120, 230, 210), true },
	cosmic = { Color3.fromRGB(80, 70, 220), true },
}
local MUTATED_COLOR = Color3.fromRGB(255, 210, 60)

local rng = Random.new()

local types = {}
for _, n in Needles do
	types[n.id] = n
end
Needle.default = types[Factory.NeedleId] or Needles[1]

local folder = Instance.new("Folder")
folder.Name = "Needles"
folder.Parent = Workspace

local held = {} -- player -> list of { id = needleId, mult = multiplier }

function Needle.info(id)
	return types[id] or Needle.default
end

-- Dollars one needle of this type and multiplier sells for at a SELL NEEDLES pad.
function Needle.priceOf(id, mult)
	return Needle.info(id).sortedValue * (mult or 1)
end

-- Dollars a needle part sells for.
function Needle.value(part)
	return Needle.priceOf(part:GetAttribute("NeedleId"), part:GetAttribute("Mutation"))
end

function Needle.isNeedle(part)
	return CollectionService:HasTag(part, "Needle")
end

-- Rolls whether a freshly found needle is mutated. Returns its multiplier (1 when it is a normal needle).
function Needle.rollMutation()
	if rng:NextNumber() < MUTATION_CHANCE then
		return rng:NextInteger(MUTATION_MIN, MUTATION_MAX)
	end
	return 1
end

-- How many needles are in this player's pocket.
function Needle.heldCount(player)
	return #(held[player] or {})
end

-- Empties the player's pocket and returns what was in it, as a list of { id = needleId, mult = multiplier }.
function Needle.takeHeld(player)
	local pocket = held[player] or {}
	held[player] = nil
	player:SetAttribute("NeedlesHeld", 0)
	return pocket
end

-- Sells everything in the player's pocket. Returns how many needles and how many dollars (the caller pays).
function Needle.sellHeld(player)
	local count, value = 0, 0
	for _, n in Needle.takeHeld(player) do
		count += 1
		value += Needle.priceOf(n.id, n.mult)
	end
	return count, value
end

local function sound(parent, id, volume)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.RollOffMaxDistance = 80
	s.Parent = parent
	s:Play()
	Debris:AddItem(s, 4)
end

-- A burst of glints at a needle.
local function glint(n, amount)
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.Lifetime = NumberRange.new(0.3, 0.6)
	e.Speed = NumberRange.new(2, 6)
	e.SpreadAngle = Vector2.new(180, 180)
	e.LightEmission = 1
	e.Color = ColorSequence.new(Color3.new(1, 1, 1), n.Color)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	e.Parent = n
	e:Emit(amount)
	Debris:AddItem(e, 1)
end

local function pickUp(player, n)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not n.Parent or (n.Position - root.Position).Magnitude > PICKUP_REACH + 2 then
		return
	end
	local id = n:GetAttribute("NeedleId") or Needle.default.id
	local mult = n:GetAttribute("Mutation") or 1
	local pocket = held[player] or {}
	table.insert(pocket, { id = id, mult = mult })
	held[player] = pocket
	player:SetAttribute("NeedlesHeld", #pocket)
	n:Destroy()
	Data.toast(
		player,
		("Picked up a %s%s needle ($%d). Sell it at a SELL NEEDLES pad."):format(
			mult > 1 and ("x%d MUTATED "):format(mult) or "",
			Needle.info(id).name:lower(),
			Needle.priceOf(id, mult)
		)
	)
end

-- Makes a needle at position. ownerId is who it belongs to while it sits in a bin. mult > 1 makes it mutated.
function Needle.spawn(position, ownerId, needleId, mult)
	needleId = needleId or Needle.default.id
	mult = mult or 1
	local look = LOOKS[needleId] or LOOKS.steel
	local n = Instance.new("Part")
	n.Name = "Needle"
	n.Shape = Enum.PartType.Cylinder
	n.Size = mult > 1 and SIZE * 1.6 or SIZE
	n.CFrame = CFrame.new(position)
	n.Color = mult > 1 and MUTATED_COLOR or look[1]
	n.Material = (mult > 1 or look[2]) and Enum.Material.Neon or Enum.Material.Metal
	n.CollisionGroup = Groups.Loose
	n:SetAttribute("OwnerId", ownerId)
	n:SetAttribute("NeedleId", needleId)
	if mult > 1 then
		n:SetAttribute("Mutation", mult)
		local sparkle = Instance.new("Sparkles")
		sparkle.SparkleColor = MUTATED_COLOR
		sparkle.Parent = n
		local light = Instance.new("PointLight")
		light.Color = MUTATED_COLOR
		light.Range = 8
		light.Brightness = 2
		light.Parent = n
	end
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

-- Same as spawn, at a CFrame (for code that already has one, like spilled hay).
function Needle.make(cframe, ownerId, needleId, mult)
	local n = Needle.spawn(cframe.Position, ownerId, needleId, mult)
	n.CFrame = cframe
	return n
end

local function announce(ownerId, needleId, mult)
	local owner = ownerId and Players:GetPlayerByUserId(ownerId)
	local text = ("%s found a x%d MUTATED %s needle worth $%d!"):format(
		owner and owner.DisplayName or "Someone",
		mult,
		Needle.info(needleId).name:lower(),
		Needle.priceOf(needleId, mult)
	)
	for _, player in Players:GetPlayers() do
		Data.toast(player, text)
	end
end

-- The reveal: a freshly found needle pops up at `from` with a flash and hangs there for a moment, spinning, then
-- arcs to land at `to`, where it glints and dings and settles with physics. Rolls the mutation chance.
function Needle.throw(from, to, ownerId, needleId)
	needleId = needleId or Needle.default.id
	local mult = Needle.rollMutation()
	local n = Needle.spawn(from, ownerId, needleId, mult)
	n.Anchored = true
	n.CanCollide = false
	local light = Instance.new("PointLight")
	light.Color = n.Color
	light.Range = 6
	light.Brightness = 3
	light.Parent = n
	glint(n, mult > 1 and 30 or 8)
	if mult > 1 then
		sound(n, FANFARE, 1)
		announce(ownerId, needleId, mult)
	end

	task.spawn(function()
		local hover = mult > 1 and 1.5 or 0.35
		local lift = from + Vector3.new(0, 1.5, 0)
		local started = os.clock()
		while n.Parent and os.clock() - started < hover do
			local t = (os.clock() - started) / hover
			n.CFrame = CFrame.new(from:Lerp(lift, math.sin(t * math.pi / 2))) * CFrame.Angles(0, t * 12, math.rad(30))
			RunService.Heartbeat:Wait()
		end
		light:Destroy()

		started = os.clock()
		local control = (lift + to) / 2 + Vector3.new(0, 4, 0)
		while n.Parent do
			local alpha = math.min((os.clock() - started) / 0.6, 1)
			local inv = 1 - alpha
			n.CFrame = CFrame.new(inv * inv * lift + 2 * inv * alpha * control + alpha * alpha * to)
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
			glint(n, 6)
			sound(n, DING, 0.35)
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
