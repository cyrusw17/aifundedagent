--!nonstrict
-- What the player looks like while working: a shovel in hand and the scoop animation.
-- Built from parts so no uploaded assets are needed yet. The swing only plays while the shovel is equipped.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config.Game)

local Avatar = {}

local rigs = {}

local function addPiece(parent, root, name, size, offset, color, material, shape)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	if shape then
		part.Shape = shape
	end
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.CFrame = root.CFrame * offset
	part.Parent = parent

	local weld = Instance.new("Weld")
	weld.Part0 = root
	weld.Part1 = part
	weld.C0 = offset
	weld.Parent = part
	return part
end

local function buildCarriedBarrel(character, root)
	local model = Instance.new("Model")
	model.Name = "CarriedBarrel"
	local upright = CFrame.Angles(0, 0, math.rad(90))
	addPiece(
		model,
		root,
		"Body",
		Vector3.new(3.4, 3, 3),
		CFrame.new(0, 0.2, -2.1) * upright,
		Color3.fromRGB(139, 90, 43),
		Enum.Material.Wood,
		Enum.PartType.Cylinder
	)
	addPiece(
		model,
		root,
		"Hay",
		Vector3.new(0.6, 2.7, 2.7),
		CFrame.new(0, 2, -2.1) * upright,
		Color3.fromRGB(232, 201, 90),
		Enum.Material.Fabric,
		Enum.PartType.Cylinder
	)
	model.Parent = character
	return model
end

local function buildShovel()
	local tool = Instance.new("Tool")
	tool.Name = "Shovel"
	tool.CanBeDropped = false
	tool.ToolTip = "Basic shovel"

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.4, 1.6, 0.4)
	handle.Color = Color3.fromRGB(139, 90, 43)
	handle.Material = Enum.Material.Wood
	handle.Parent = tool

	local function attach(name, size, offset, color, material)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.Color = color
		part.Material = material
		part.CanCollide = false
		part.Massless = true
		part.CFrame = handle.CFrame * offset
		part.Parent = tool
		local weld = Instance.new("Weld")
		weld.Part0 = handle
		weld.Part1 = part
		weld.C0 = offset
		weld.Parent = part
	end

	-- The shaft and blade point out of the top of the handle, so the blade leads when the arm reaches forward.
	attach("Shaft", Vector3.new(0.4, 3, 0.4), CFrame.new(0, 2.3, 0), Color3.fromRGB(139, 90, 43), Enum.Material.Wood)
	attach(
		"Blade",
		Vector3.new(1.2, 1.5, 0.12),
		CFrame.new(0, 4.35, 0),
		Color3.fromRGB(150, 158, 166),
		Enum.Material.Metal
	)
	return tool
end

-- Finds a shoulder joint for either rig type. side is "Right" or "Left".
local function findShoulder(character, side)
	local upper = character:WaitForChild(side .. "UpperArm", 3)
	if upper then
		return upper:WaitForChild(side .. "Shoulder", 3)
	end
	local torso = character:FindFirstChild("Torso")
	if torso then
		return torso:FindFirstChild(side .. " Shoulder")
	end
	return nil
end

local function tweenMotor(motor, base, degrees, seconds, style)
	if not motor or not motor.Parent or not base then
		return
	end
	local goal = { C0 = base * CFrame.Angles(math.rad(degrees), 0, 0) }
	TweenService:Create(motor, TweenInfo.new(seconds, style or Enum.EasingStyle.Sine, Enum.EasingDirection.Out), goal)
		:Play()
end

local function tweenArm(rig, degrees, seconds, style)
	tweenMotor(rig.motor, rig.base, degrees, seconds, style)
end

-- The shovel is a child of the character only while it is equipped (otherwise it sits in the Backpack).
function Avatar.hasShovelEquipped(player)
	local character = player.Character
	return character ~= nil and character:FindFirstChild("Shovel") ~= nil
end

local function setup(player, character)
	local humanoid = character:WaitForChild("Humanoid")
	local root = character:WaitForChild("HumanoidRootPart")
	local motor = findShoulder(character, "Right")
	local leftMotor = findShoulder(character, "Left")

	local rig = {
		character = character,
		humanoid = humanoid,
		root = root,
		motor = motor,
		base = motor and motor.C0,
		leftMotor = leftMotor,
		leftBase = leftMotor and leftMotor.C0,
		defaultSpeed = humanoid.WalkSpeed,
		token = 0,
		digging = false,
		liftUntil = 0,
		carrying = false,
		carryModel = nil,
	}
	rigs[player] = rig

	-- No shovel while carrying a barrel.
	character.ChildAdded:Connect(function(child)
		if rig.carrying and child:IsA("Tool") then
			task.defer(function()
				humanoid:UnequipTools()
			end)
		end
	end)

	local backpack = player:WaitForChild("Backpack")
	local shovel = buildShovel()
	shovel.Parent = backpack
	humanoid:EquipTool(shovel)
end

-- Both arms hold a barrel in front of the chest; walking slows down and the shovel is put away.
function Avatar.setCarry(player)
	local rig = rigs[player]
	if not rig or rig.carrying then
		return
	end
	rig.carrying = true
	rig.token += 1
	rig.digging = false
	rig.humanoid:UnequipTools()
	rig.humanoid.WalkSpeed = Config.CarryWalkSpeed
	rig.carryModel = buildCarriedBarrel(rig.character, rig.root)
	tweenMotor(rig.motor, rig.base, 80, 0.25)
	tweenMotor(rig.leftMotor, rig.leftBase, 80, 0.25)
end

function Avatar.clearCarry(player)
	local rig = rigs[player]
	if not rig or not rig.carrying then
		return
	end
	rig.carrying = false
	if rig.carryModel then
		rig.carryModel:Destroy()
		rig.carryModel = nil
	end
	rig.humanoid.WalkSpeed = rig.defaultSpeed
	tweenMotor(rig.motor, rig.base, 0, 0.25)
	tweenMotor(rig.leftMotor, rig.leftBase, 0, 0.25)
	local shovel = player.Backpack:FindFirstChild("Shovel")
	if shovel then
		rig.humanoid:EquipTool(shovel)
	end
end

-- Pumping motion while the player holds the prompt. `burst` is called on every downward thrust.
function Avatar.startDig(player, burst)
	local rig = rigs[player]
	if not rig or not Avatar.hasShovelEquipped(player) then
		return
	end
	rig.token += 1
	local token = rig.token
	rig.digging = true
	task.spawn(function()
		while rig.token == token and rig.digging do
			if not Avatar.hasShovelEquipped(player) then
				rig.digging = false
				tweenArm(rig, 0, 0.2)
				break
			end
			tweenArm(rig, Config.DigBackDegrees, Config.DigBackSeconds)
			task.wait(Config.DigBackSeconds)
			if rig.token ~= token or not rig.digging then
				break
			end
			tweenArm(rig, Config.DigForwardDegrees, Config.DigForwardSeconds, Enum.EasingStyle.Quad)
			task.wait(Config.DigForwardSeconds)
			if burst and rig.token == token then
				burst()
			end
		end
	end)
end

function Avatar.stopDig(player)
	local rig = rigs[player]
	if not rig then
		return
	end
	rig.digging = false
	if os.clock() < rig.liftUntil then
		return
	end
	rig.token += 1
	tweenArm(rig, 0, 0.2)
end

-- Raise the full shovel after a scoop, then settle back.
function Avatar.lift(player)
	local rig = rigs[player]
	if not rig or not Avatar.hasShovelEquipped(player) then
		return
	end
	rig.token += 1
	rig.digging = false
	rig.liftUntil = os.clock() + 0.6
	local token = rig.token
	tweenArm(rig, Config.LiftDegrees, 0.2, Enum.EasingStyle.Quad)
	task.delay(0.35, function()
		if rig.token == token then
			tweenArm(rig, 0, 0.3)
		end
	end)
end

-- A clump of hay arcs from the barrel to the player's chest, where it joins the load they are carrying.
function Avatar.flyHay(player, fromPosition)
	local rig = rigs[player]
	if not rig or not Avatar.hasShovelEquipped(player) then
		return
	end

	local clump = Instance.new("Part")
	clump.Name = "HayClump"
	clump.Size = Vector3.new(0.9, 0.5, 0.9)
	clump.Color = Color3.fromRGB(232, 201, 90)
	clump.Material = Enum.Material.Fabric
	clump.Anchored = true
	clump.CanCollide = false
	clump.CanQuery = false
	clump.CanTouch = false
	clump.Position = fromPosition
	clump.Parent = workspace

	task.spawn(function()
		local started = os.clock()
		local duration = Config.HayFlightSeconds
		while true do
			local alpha = (os.clock() - started) / duration
			if alpha >= 1 or not rig.root.Parent then
				break
			end
			local target = rig.root.Position + Vector3.new(0, 1, 0)
			local control = (fromPosition + target) / 2 + Vector3.new(0, 5, 0)
			local inv = 1 - alpha
			clump.Position = inv * inv * fromPosition + 2 * inv * alpha * control + alpha * alpha * target
			clump.CFrame = clump.CFrame * CFrame.Angles(0.15, 0.2, 0)
			RunService.Heartbeat:Wait()
		end
		clump:Destroy()
	end)
end

function Avatar.start()
	local function onPlayer(player)
		player.CharacterAdded:Connect(function(character)
			task.spawn(setup, player, character)
		end)
		if player.Character then
			task.spawn(setup, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		rigs[player] = nil
	end)
end

return Avatar
