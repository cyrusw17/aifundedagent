--!nonstrict
-- Hay barrels. Bare hands lift a whole barrel and carry it. The shovel smashes it open: the staves fly apart and
-- the hay spills into a pile of loose pieces (see Hay.luau). A set-down barrel falls and rolls like any object.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Shared.Config.Game)
local Data = require(script.Parent.Data)
local Avatar = require(script.Parent.Avatar)
local Hay = require(script.Parent.Hay)
local Groups = require(script.Parent.Groups)

local Barrels = {}

local rng = Random.new()
local folder = nil
local dropOff = nil -- the pad where set-down barrels are kept for later
local byBody = {} -- barrel body part -> barrel record

local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- cylinders run along X, so this stands them up
local HAY_BASE = CFrame.new(2.6, 0, 0) -- the hay sits on the top end of the barrel, along its X axis
local CARRY_OFFSET = CFrame.new(0, 0.3, -2.6) * UPRIGHT
local WOOD = Color3.fromRGB(139, 90, 43)
local HAY = Color3.fromRGB(232, 201, 90)

local function buildBarrel(position)
	local body = Instance.new("Part")
	body.Name = "HayBarrel"
	body.Shape = Enum.PartType.Cylinder
	body.Size = Vector3.new(5, 4, 4)
	body.CFrame = CFrame.new(position + Vector3.new(0, 2.5, 0)) * UPRIGHT
	body.Color = WOOD
	body.Material = Enum.Material.Wood
	body.Anchored = true
	body.CustomPhysicalProperties = PhysicalProperties.new(0.6, 0.8, 0.2, 1, 1)

	local hay = Instance.new("Part")
	hay.Name = "HayTop"
	hay.Shape = Enum.PartType.Cylinder
	hay.Size = Vector3.new(0.8, 3.6, 3.6)
	hay.CFrame = body.CFrame * HAY_BASE
	hay.Color = HAY
	hay.Material = Enum.Material.Fabric
	hay.CanCollide = false
	hay.Massless = true
	hay.Parent = body

	local weld = Instance.new("Weld")
	weld.Part0 = body
	weld.Part1 = hay
	weld.C0 = HAY_BASE
	weld.Parent = hay

	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = Config.PickupReach
	click.Parent = body

	CollectionService:AddTag(body, "HayBarrel")
	return body, hay, click
end

-- Removes a barrel from the world for good (sold, smashed, or timed out).
function Barrels.consume(b)
	if b.gone then
		return
	end
	b.gone = true
	byBody[b.body] = nil
	b.body:Destroy()
end

function Barrels.fromPart(part)
	return byBody[part] or (part.Parent and byBody[part.Parent]) or nil
end

-- True when the barrel rests on the drop-off pad (checked in the pad's own flat space, ignoring height).
function Barrels.isAtDropOff(b)
	if not dropOff or b.gone then
		return false
	end
	local spot = dropOff.CFrame:PointToObjectSpace(b.body.Position)
	return math.abs(spot.X) <= dropOff.Size.X / 2 and math.abs(spot.Z) <= dropOff.Size.Z / 2 and spot.Y < 8
end

-- Barrels left out in the world disappear after a while. Barrels on the drop-off pad are kept.
local function startDespawnTimer(b)
	b.dropToken += 1
	local token = b.dropToken
	local function check()
		if b.gone or b.carriedBy or b.home or b.dropToken ~= token then
			return
		end
		if Barrels.isAtDropOff(b) then
			task.delay(Config.DroppedBarrelSeconds, check) -- still stored, look again later
			return
		end
		Barrels.consume(b)
	end
	task.delay(Config.DroppedBarrelSeconds, check)
end

function Barrels.setDropOff(part)
	dropOff = part
end

-- A home barrel is gone from its spot (smashed or lifted), so a fresh one grows back there.
local function scheduleRegrow(b)
	if not b.home then
		return
	end
	b.home = false
	task.delay(Config.BarrelRefillSeconds, function()
		Barrels.spawn(b.spawnPosition, true, true)
	end)
end

local function debrisPart(shape, size, cframe, color, material, velocity)
	local part = Instance.new("Part")
	part.Shape = shape
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.CollisionGroup = Groups.Loose
	part.AssemblyLinearVelocity = velocity
	part.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-10, 10), rng:NextNumber(-10, 10), rng:NextNumber(-10, 10))
	part.Parent = Hay.folder
	task.delay(7, function()
		if part.Parent then
			TweenService:Create(part, TweenInfo.new(1), { Transparency = 1 }):Play()
			Debris:AddItem(part, 1.1)
		end
	end)
	return part
end

-- Straw and dust thrown up when the barrel bursts.
local function burstEffects(position)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Position = position
	anchor.Parent = Hay.folder

	local straw = Instance.new("ParticleEmitter")
	straw.Rate = 0
	straw.Lifetime = NumberRange.new(0.6, 1.1)
	straw.Speed = NumberRange.new(10, 22)
	straw.SpreadAngle = Vector2.new(180, 180)
	straw.Acceleration = Vector3.new(0, -25, 0)
	straw.Color = ColorSequence.new(HAY)
	straw.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	straw.Parent = anchor

	local dust = Instance.new("ParticleEmitter")
	dust.Rate = 0
	dust.Lifetime = NumberRange.new(0.8, 1.4)
	dust.Speed = NumberRange.new(3, 8)
	dust.SpreadAngle = Vector2.new(180, 180)
	dust.Color = ColorSequence.new(Color3.fromRGB(200, 180, 140))
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 5) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	dust.Parent = anchor

	straw:Emit(40)
	dust:Emit(18)
	Debris:AddItem(anchor, 2.5)
end

-- The shovel smashes a barrel open: it shudders, the staves and hoops burst outward, and the hay
-- pours out in three waves into a pile.
function Barrels.breakOpen(player, b)
	if b.gone or b.carriedBy or b.breaking then
		return
	end
	b.breaking = true
	b.click.MaxActivationDistance = 0
	scheduleRegrow(b)

	task.spawn(function()
		local body = b.body
		body.Anchored = true
		body.AssemblyLinearVelocity = Vector3.zero
		local rest = body.CFrame
		for _ = 1, 6 do
			body.CFrame = rest * CFrame.new(rng:NextNumber(-0.2, 0.2), rng:NextNumber(-0.1, 0.1), rng:NextNumber(-0.2, 0.2))
			task.wait(0.04)
		end

		local center = rest.Position
		Barrels.consume(b)
		burstEffects(center + Vector3.new(0, 1.5, 0))

		local barrelOwner = player.UserId
		for i = 1, 12 do
			local angle = (i / 12) * math.pi * 2
			local radial = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local cframe = CFrame.new(center + radial * 1.85) * CFrame.Angles(0, -angle, 0)
			debrisPart(
				Enum.PartType.Block,
				Vector3.new(0.35, 4.6, 1.0),
				cframe,
				WOOD,
				Enum.Material.Wood,
				radial * rng:NextNumber(10, 18) + Vector3.new(0, rng:NextNumber(8, 16), 0)
			)
		end
		for _, y in { -1.4, 1.4 } do
			debrisPart(
				Enum.PartType.Cylinder,
				Vector3.new(0.25, 4.3, 4.3),
				CFrame.new(center + Vector3.new(0, y, 0)) * UPRIGHT,
				Color3.fromRGB(70, 70, 76),
				Enum.Material.Metal,
				Vector3.new(rng:NextNumber(-4, 4), rng:NextNumber(6, 10), rng:NextNumber(-4, 4))
			)
		end
		debrisPart(
			Enum.PartType.Cylinder,
			Vector3.new(0.4, 3.8, 3.8),
			CFrame.new(center + Vector3.new(0, -2.2, 0)) * UPRIGHT,
			WOOD,
			Enum.Material.Wood,
			Vector3.new(rng:NextNumber(-3, 3), 3, rng:NextNumber(-3, 3))
		)

		-- The hay pours out in waves so it looks like it spills, not like it teleports.
		local waves = 3
		local perWave = math.ceil(Config.PiecesPerBarrel / waves)
		for wave = 1, waves do
			for _ = 1, perWave do
				local offset = Vector3.new(rng:NextNumber(-1.2, 1.2), 2 + wave * 0.5, rng:NextNumber(-1.2, 1.2))
				local velocity = Vector3.new(rng:NextNumber(-4, 4), rng:NextNumber(3, 8), rng:NextNumber(-4, 4))
				Hay.spawnPiece(center + offset, velocity, barrelOwner)
			end
			task.wait(0.22)
		end
	end)
end

function Barrels.pickup(player, b)
	local state = Data.get(player)
	local root = Avatar.getRoot(player)
	if not state or not root or state.carryBarrel or b.gone or b.carriedBy or b.breaking then
		return
	end
	if Avatar.equippedKind(player) ~= nil then
		return -- only bare hands lift a whole barrel
	end
	if (b.body.Position - root.Position).Magnitude > Config.PickupReach + 4 then
		return
	end

	b.carriedBy = player
	b.ownerId = player.UserId
	b.dropToken += 1
	state.carryBarrel = b

	-- The barrel itself is welded in front of the player, so what you carry is the real barrel.
	b.body.Anchored = false
	b.body.CanCollide = false
	b.body.Massless = true
	b.body.CFrame = root.CFrame * CARRY_OFFSET
	local weld = Instance.new("Weld")
	weld.Name = "CarryWeld"
	weld.Part0 = root
	weld.Part1 = b.body
	weld.C0 = CARRY_OFFSET
	weld.Parent = b.body
	b.carryWeld = weld
	b.click.MaxActivationDistance = 0

	scheduleRegrow(b)
	Avatar.setCarry(player)
	Data.sync(player)
end

-- Put the carried barrel down with a small toss. It lands and rolls like any physical object.
function Barrels.drop(player)
	local state = Data.get(player)
	local b = state and state.carryBarrel
	if not b or b.gone then
		return
	end
	local root = Avatar.getRoot(player)
	state.carryBarrel = nil
	Data.sync(player)

	if b.carryWeld then
		b.carryWeld:Destroy()
		b.carryWeld = nil
	end
	b.carriedBy = nil

	if not root or not root.Parent then
		Barrels.consume(b)
		return
	end

	local look = root.CFrame.LookVector
	b.body.CFrame = CFrame.new(root.Position + look * 4 + Vector3.new(0, 1, 0)) * UPRIGHT
	b.body.Massless = false
	b.body.CanCollide = true
	b.body.Anchored = false
	b.body.AssemblyLinearVelocity = look * 8 + Vector3.new(0, 4, 0)
	b.click.MaxActivationDistance = Config.PickupReach
	pcall(function()
		b.body:SetNetworkOwner(nil) -- the server keeps control so every player sees the same barrel
	end)

	Avatar.clearCarry(player)
	startDespawnTimer(b)
end

-- position is the ground point under the barrel. home barrels regrow after being smashed or lifted.
function Barrels.spawn(position, home, fadeIn)
	local body, hay, click = buildBarrel(position)
	local b = {
		body = body,
		hay = hay,
		click = click,
		home = home,
		spawnPosition = position,
		carriedBy = nil,
		ownerId = nil,
		carryWeld = nil,
		dropToken = 0,
		breaking = false,
		gone = false,
	}
	byBody[body] = b
	body.Parent = folder

	if fadeIn then
		body.Transparency = 1
		hay.Transparency = 1
		local info = TweenInfo.new(0.7)
		TweenService:Create(body, info, { Transparency = 0 }):Play()
		TweenService:Create(hay, info, { Transparency = 0 }):Play()
	end

	-- Clicking with bare hands lifts the barrel. Tools are handled by Tools.luau.
	click.MouseClick:Connect(function(player)
		if Avatar.equippedKind(player) == nil then
			Barrels.pickup(player, b)
		end
	end)
end

function Barrels.init(worldFolder)
	folder = worldFolder

	local function watch(player)
		local function onCharacter(character)
			local humanoid = character:WaitForChild("Humanoid")
			humanoid.Died:Connect(function()
				Barrels.drop(player)
			end)
		end
		player.CharacterAdded:Connect(onCharacter)
		if player.Character then
			task.spawn(onCharacter, player.Character)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end

	-- A barrel does not stay stuck to a player who left the game.
	Players.PlayerRemoving:Connect(function(player)
		for _, b in byBody do
			if b.carriedBy == player then
				Barrels.consume(b)
			end
		end
	end)
end

return Barrels
