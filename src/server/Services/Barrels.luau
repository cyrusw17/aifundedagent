--!nonstrict
-- Hay barrels: scooping from them, picking one up whole, and putting one down again.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config.Game)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Data = require(script.Parent.Data)
local Avatar = require(script.Parent.Avatar)

local Barrels = {}

local rng = Random.new()
local folder = nil

local function addPrompt(parent, key, actionText, holdSeconds, uiOffset)
	local prompt = Instance.new("ProximityPrompt")
	prompt.KeyboardKeyCode = key
	prompt.ActionText = actionText
	prompt.ObjectText = "Hay barrel"
	prompt.HoldDuration = holdSeconds
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.UIOffset = uiOffset
	prompt.Parent = parent
	return prompt
end

local function buildBarrelPart(position)
	local barrel = Instance.new("Part")
	barrel.Name = "HayBarrel"
	barrel.Shape = Enum.PartType.Cylinder
	barrel.Size = Vector3.new(5, 4, 4) -- cylinders run along X, so it is turned upright below
	barrel.CFrame = CFrame.new(position + Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
	barrel.Color = Color3.fromRGB(139, 90, 43)
	barrel.Material = Enum.Material.Wood
	barrel.Anchored = true

	local hay = Instance.new("Part")
	hay.Name = "HayTop"
	hay.Shape = Enum.PartType.Cylinder
	hay.Size = Vector3.new(0.8, 3.6, 3.6)
	hay.CFrame = CFrame.new(position + Vector3.new(0, 5.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	hay.Color = Color3.fromRGB(232, 201, 90)
	hay.Material = Enum.Material.Fabric
	hay.Anchored = true
	hay.CanCollide = false
	hay.Parent = barrel

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

	return barrel, hay, burst
end

-- position is the ground point under the barrel. home barrels refill or respawn at the same spot.
function Barrels.spawn(position, scoops, home)
	local barrel, hayTop, burst = buildBarrelPart(position)
	barrel.Parent = folder

	local baseCFrame = hayTop.CFrame
	local scoopsLeft = scoops
	local gone = false

	local scoopPrompt = addPrompt(barrel, Enum.KeyCode.E, "Scoop hay", Config.ScoopHoldSeconds, Vector2.new(0, 0))
	local pickupPrompt =
		addPrompt(barrel, Enum.KeyCode.F, "Pick up barrel", Config.BarrelPickupHoldSeconds, Vector2.new(0, 75))
	barrel:SetAttribute("Scoops", scoopsLeft)

	local function showFill(instant)
		if scoopsLeft <= 0 then
			hayTop.Transparency = 1
			return
		end
		hayTop.Transparency = 0
		local drop = (1 - scoopsLeft / Config.BarrelScoops) * 2.4
		local goal = baseCFrame - Vector3.new(0, drop, 0)
		if instant then
			hayTop.CFrame = goal
		else
			TweenService:Create(hayTop, TweenInfo.new(0.2), { CFrame = goal }):Play()
		end
	end
	showFill(true)

	scoopPrompt.PromptButtonHoldBegan:Connect(function(player)
		if scoopsLeft > 0 then
			Avatar.startDig(player, function()
				burst:Emit(8)
			end)
		end
	end)

	scoopPrompt.PromptButtonHoldEnded:Connect(function(player)
		Avatar.stopDig(player)
	end)

	scoopPrompt.Triggered:Connect(function(player)
		local state = Data.get(player)
		if gone or not state or scoopsLeft <= 0 then
			return
		end
		if state.carry then
			Data.toast(player, "Put your barrel down before you scoop.")
			return
		end
		if not Avatar.hasShovelEquipped(player) then
			Data.toast(player, "Equip your shovel to scoop hay.")
			return
		end

		local hay = Config.ShovelHayPerScoop
		if state.loadHay + hay > Config.WheelbarrowCapacity then
			Data.toast(player, "You are carrying all the hay you can. Take it to the hay shop.")
			Avatar.stopDig(player)
			return
		end

		scoopsLeft -= 1
		state.loadHay += hay
		state.loadNeedles += Economy.rollNeedles(rng, hay, Config.NeedleChancePerHay)
		barrel:SetAttribute("Scoops", scoopsLeft)
		Data.sync(player)
		showFill(false)

		Avatar.lift(player)
		burst:Emit(14)
		Avatar.flyHay(player, hayTop.Position)

		if scoopsLeft <= 0 then
			scoopPrompt.Enabled = false
			pickupPrompt.Enabled = false
			if home then
				task.delay(Config.BarrelRefillSeconds, function()
					if gone then
						return
					end
					scoopsLeft = Config.BarrelScoops
					barrel:SetAttribute("Scoops", scoopsLeft)
					showFill(true)
					scoopPrompt.Enabled = true
					pickupPrompt.Enabled = true
				end)
			else
				task.delay(2, function()
					barrel:Destroy()
				end)
			end
		end
	end)

	pickupPrompt.Triggered:Connect(function(player)
		local state = Data.get(player)
		if gone or not state or scoopsLeft <= 0 then
			return
		end
		if state.carry then
			Data.toast(player, "You are already carrying a barrel.")
			return
		end
		gone = true
		state.carry = scoopsLeft
		Data.sync(player)
		Avatar.setCarry(player)
		barrel:Destroy()
		if home then
			task.delay(Config.BarrelRefillSeconds, function()
				Barrels.spawn(position, Config.BarrelScoops, true)
			end)
		end
	end)

	if not home then
		task.delay(Config.DroppedBarrelSeconds, function()
			if barrel.Parent then
				gone = true
				barrel:Destroy()
			end
		end)
	end
end

function Barrels.drop(player)
	local state = Data.get(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not state or not state.carry or not root then
		return
	end

	local origin = root.Position + root.CFrame.LookVector * 4
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local hit = Workspace:Raycast(origin + Vector3.new(0, 4, 0), Vector3.new(0, -30, 0), params)
	local groundY = hit and hit.Position.Y or (root.Position.Y - 3)

	local scoops = state.carry
	state.carry = nil
	Data.sync(player)
	Avatar.clearCarry(player)
	Barrels.spawn(Vector3.new(origin.X, groundY, origin.Z), scoops, false)
end

function Barrels.init(worldFolder)
	folder = worldFolder

	local remote = Instance.new("RemoteEvent")
	remote.Name = "DropBarrel"
	remote.Parent = ReplicatedStorage
	remote.OnServerEvent:Connect(function(player)
		Barrels.drop(player)
	end)

	-- A barrel being carried is lost if the player respawns.
	local function watch(player)
		player.CharacterAdded:Connect(function()
			local state = Data.get(player)
			if state and state.carry then
				state.carry = nil
				Data.sync(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return Barrels
