--!nonstrict
-- Hay barrels. Each one is a real physical object: scoop it with the shovel, lift it with empty hands,
-- carry it, set it down (it falls and rolls) and sell it on the sell pad. No prompts or overlays, just clicks.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config.Game)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Data = require(script.Parent.Data)
local Avatar = require(script.Parent.Avatar)

local Barrels = {}

local rng = Random.new()
local folder = nil
local byBody = {} -- barrel body part -> barrel record

local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- cylinders run along X, so this stands them up
local HAY_BASE = CFrame.new(2.6, 0, 0) -- the hay sits on the top end of the barrel, along its X axis
local CARRY_OFFSET = CFrame.new(0, 0.3, -2.6) * UPRIGHT

local function buildBarrel(position)
	local body = Instance.new("Part")
	body.Name = "HayBarrel"
	body.Shape = Enum.PartType.Cylinder
	body.Size = Vector3.new(5, 4, 4)
	body.CFrame = CFrame.new(position + Vector3.new(0, 2.5, 0)) * UPRIGHT
	body.Color = Color3.fromRGB(139, 90, 43)
	body.Material = Enum.Material.Wood
	body.Anchored = true
	body.CustomPhysicalProperties = PhysicalProperties.new(0.6, 0.8, 0.2, 1, 1)

	local hay = Instance.new("Part")
	hay.Name = "HayTop"
	hay.Shape = Enum.PartType.Cylinder
	hay.Size = Vector3.new(0.8, 3.6, 3.6)
	hay.CFrame = body.CFrame * HAY_BASE
	hay.Color = Color3.fromRGB(232, 201, 90)
	hay.Material = Enum.Material.Fabric
	hay.CanCollide = false
	hay.Massless = true
	hay.Parent = body

	local weld = Instance.new("Weld")
	weld.Part0 = body
	weld.Part1 = hay
	weld.C0 = HAY_BASE
	weld.Parent = hay

	local burst = Instance.new("ParticleEmitter")
	burst.Name = "HayBurst"
	burst.Rate = 0
	burst.Lifetime = NumberRange.new(0.5, 0.9)
	burst.Speed = NumberRange.new(8, 14)
	burst.SpreadAngle = Vector2.new(40, 40)
	burst.Acceleration = Vector3.new(0, -30, 0)
	burst.Color = ColorSequence.new(Color3.fromRGB(232, 201, 90))
	burst.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	burst.Parent = hay

	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = 14
	click.Parent = body

	return body, hay, weld, burst, click
end

local function showFill(b, instant)
	if b.scoops <= 0 then
		b.hay.Transparency = 1
		return
	end
	b.hay.Transparency = 0
	local drop = (1 - b.scoops / Config.BarrelScoops) * 2.4
	local goal = HAY_BASE * CFrame.new(-drop, 0, 0)
	if instant then
		b.hayWeld.C0 = goal
	else
		TweenService:Create(b.hayWeld, TweenInfo.new(0.2), { C0 = goal }):Play()
	end
end

-- Removes a barrel from the world for good (sold, emptied away from home, or timed out).
function Barrels.consume(b)
	if b.gone then
		return
	end
	b.gone = true
	byBody[b.body] = nil
	b.body:Destroy()
end

function Barrels.fromPart(part)
	return byBody[part]
end

local function startDespawnTimer(b)
	b.dropToken += 1
	local token = b.dropToken
	task.delay(Config.DroppedBarrelSeconds, function()
		if not b.gone and not b.carriedBy and not b.home and b.dropToken == token then
			Barrels.consume(b)
		end
	end)
end

local function scoopClick(player, b)
	local state = Data.get(player)
	if not state then
		return
	end
	local hay = Config.ShovelHayPerScoop
	if state.loadHay + hay > Config.WheelbarrowCapacity then
		Data.toast(player, "You are carrying all the hay you can. Sell it at the pad by the shop.")
		return
	end
	if b.scoops <= 0 then
		return
	end

	Avatar.scoopSwing(player, function()
		-- The swing takes a moment, so check everything again when the shovel lands.
		if b.gone or b.carriedBy or b.scoops <= 0 or state.loadHay + hay > Config.WheelbarrowCapacity then
			return
		end
		b.scoops -= 1
		b.body:SetAttribute("Scoops", b.scoops)
		state.loadHay += hay
		state.loadNeedles += Economy.rollNeedles(rng, hay, Config.NeedleChancePerHay)
		Data.sync(player)
		showFill(b, false)
		b.burst:Emit(14)
		Avatar.flyHay(player, b.hay.Position)

		if b.scoops <= 0 then
			b.click.MaxActivationDistance = 0
			if b.home then
				task.delay(Config.BarrelRefillSeconds, function()
					if b.gone or not b.home then
						return
					end
					b.scoops = Config.BarrelScoops
					b.body:SetAttribute("Scoops", b.scoops)
					showFill(b, true)
					b.click.MaxActivationDistance = 14
				end)
			else
				task.delay(2, function()
					Barrels.consume(b)
				end)
			end
		end
	end)
end

local function pickupClick(player, b)
	local state = Data.get(player)
	local root = Avatar.getRoot(player)
	if not state or not root or state.carryBarrel or b.scoops <= 0 then
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

	-- A home barrel left its spot, so a fresh one grows back there.
	if b.home then
		b.home = false
		task.delay(Config.BarrelRefillSeconds, function()
			Barrels.spawn(b.spawnPosition, Config.BarrelScoops, true)
		end)
	end

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
	b.click.MaxActivationDistance = 14
	pcall(function()
		b.body:SetNetworkOwner(nil) -- the server keeps control so every player sees the same barrel
	end)

	Avatar.clearCarry(player)
	startDespawnTimer(b)
end

-- position is the ground point under the barrel. home barrels refill, and regrow after being picked up.
function Barrels.spawn(position, scoops, home)
	local body, hay, hayWeld, burst, click = buildBarrel(position)
	local b = {
		body = body,
		hay = hay,
		hayWeld = hayWeld,
		burst = burst,
		click = click,
		scoops = scoops,
		home = home,
		spawnPosition = position,
		carriedBy = nil,
		ownerId = nil,
		carryWeld = nil,
		dropToken = 0,
		gone = false,
	}
	byBody[body] = b
	body:SetAttribute("Scoops", scoops)
	showFill(b, true)
	body.Parent = folder

	click.MouseClick:Connect(function(player)
		if b.gone or b.carriedBy then
			return
		end
		if Avatar.hasShovelEquipped(player) then
			scoopClick(player, b)
		else
			pickupClick(player, b)
		end
	end)
end

function Barrels.init(worldFolder)
	folder = worldFolder

	local remote = Instance.new("RemoteEvent")
	remote.Name = "DropBarrel"
	remote.Parent = ReplicatedStorage
	remote.OnServerEvent:Connect(function(player)
		Barrels.drop(player)
	end)

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
