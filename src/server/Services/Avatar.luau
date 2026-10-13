--!nonstrict
-- What the player looks like while working: the shovel and rake, their swings, and the carry pose.
-- Built from parts so no uploaded assets are needed yet. Each swing only plays with its own tool equipped.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config.Game)
local Groups = require(script.Parent.Groups)

local Avatar = {}

Avatar.onToolActivated = nil -- set by Tools.init: function(player, kind) for each click with a tool

local rigs = {}

local WOOD = Color3.fromRGB(139, 90, 43)

-- A tool with a wooden handle plus extra welded parts. parts is a list of { name, size, offset, color, material }.
local function buildTool(name, tip, parts)
	local tool = Instance.new("Tool")
	tool.Name = name
	tool.CanBeDropped = false
	tool.ToolTip = tip

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.4, 1.6, 0.4)
	handle.Color = WOOD
	handle.Material = Enum.Material.Wood
	handle.Parent = tool

	for _, def in parts do
		local part = Instance.new("Part")
		part.Name = def[1]
		part.Size = def[2]
		part.Color = def[4]
		part.Material = def[5]
		part.CanCollide = false
		part.Massless = true
		part.CFrame = handle.CFrame * def[3]
		part.Parent = tool
		local weld = Instance.new("Weld")
		weld.Part0 = handle
		weld.Part1 = part
		weld.C0 = def[3]
		weld.Parent = part
	end
	return tool
end

-- The shaft and blade point out of the top of the handle, so the blade leads when the arm reaches forward.
local function buildShovel()
	return buildTool("Shovel", "Face a barrel to smash it, or a pile to scoop it, and click.", {
		{ "Shaft", Vector3.new(0.4, 3, 0.4), CFrame.new(0, 2.3, 0), WOOD, Enum.Material.Wood },
		{
			"Blade",
			Vector3.new(1.2, 1.5, 0.12),
			CFrame.new(0, 4.35, 0),
			Color3.fromRGB(150, 158, 166),
			Enum.Material.Metal,
		},
	})
end

-- A long shaft with a crossbar and a row of teeth at the end.
local function buildRake()
	local steel = Color3.fromRGB(150, 158, 166)
	local parts = {
		{ "Shaft", Vector3.new(0.4, 3.6, 0.4), CFrame.new(0, 2.6, 0), WOOD, Enum.Material.Wood },
		{ "Bar", Vector3.new(3.2, 0.25, 0.3), CFrame.new(0, 4.5, 0), steel, Enum.Material.Metal },
	}
	for i = 0, 5 do
		table.insert(parts, {
			"Tooth" .. i,
			Vector3.new(0.12, 1, 0.12),
			CFrame.new(-1.4 + i * 0.56, 5.1, 0),
			steel,
			Enum.Material.Metal,
		})
	end
	return buildTool("Rake", "Face loose hay and click to drag it toward you.", parts)
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

-- A tool is a child of the character only while it is equipped (otherwise it sits in the Backpack).
-- Returns "Shovel", "Rake", or nil for bare hands.
function Avatar.equippedKind(player)
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	return tool and tool.Name or nil
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
		swingUntil = 0,
		carrying = false,
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

	-- Characters sit in their own collision group so loose hay never trips or flings them.
	local function groupPart(part)
		if part:IsA("BasePart") then
			part.CollisionGroup = Groups.Players
		end
	end
	for _, part in character:GetDescendants() do
		groupPart(part)
	end
	character.DescendantAdded:Connect(groupPart)

	-- A click with a tool in hand fires its Activated signal on the server too, so tools need no client code.
	local function hook(tool)
		tool.Activated:Connect(function()
			if Avatar.onToolActivated then
				Avatar.onToolActivated(player, tool.Name)
			end
		end)
		return tool
	end

	local backpack = player:WaitForChild("Backpack")
	local shovel = hook(buildShovel())
	shovel.Parent = backpack
	hook(buildRake()).Parent = backpack
	humanoid:EquipTool(shovel)
end

-- One swing of the equipped tool. onImpact runs at the moment the tool lands. Returns false if it could not start.
function Avatar.swing(player, kind, onImpact)
	local rig = rigs[player]
	if not rig or rig.carrying or Avatar.equippedKind(player) ~= kind then
		return false
	end
	if os.clock() < rig.swingUntil then
		return false
	end
	local cooldown = kind == "Rake" and Config.RakeCooldownSeconds or Config.ScoopCooldownSeconds
	rig.swingUntil = os.clock() + cooldown
	rig.token += 1
	local token = rig.token

	task.spawn(function()
		if kind == "Rake" then
			-- Reach out over the hay, then drag the teeth back toward the body.
			tweenArm(rig, Config.RakeReachDegrees, 0.2)
			task.wait(0.2)
			if rig.token ~= token then
				return
			end
			tweenArm(rig, Config.RakeDragDegrees, 0.3, Enum.EasingStyle.Quad)
			task.wait(0.1)
			if rig.token ~= token then
				return
			end
			if Avatar.equippedKind(player) == kind then
				onImpact()
			end
			task.wait(0.25)
			if rig.token == token then
				tweenArm(rig, 0, 0.25)
			end
			return
		end

		tweenArm(rig, Config.DigBackDegrees, Config.DigBackSeconds)
		task.wait(Config.DigBackSeconds)
		if rig.token ~= token then
			return
		end
		tweenArm(rig, Config.DigForwardDegrees, Config.DigForwardSeconds, Enum.EasingStyle.Quad)
		task.wait(Config.DigForwardSeconds)
		if rig.token ~= token then
			return
		end
		if Avatar.equippedKind(player) == kind then
			onImpact()
		end
		tweenArm(rig, Config.LiftDegrees, 0.2, Enum.EasingStyle.Quad)
		task.wait(0.3)
		if rig.token == token then
			tweenArm(rig, 0, 0.25)
		end
	end)
	return true
end

-- Both arms hold a barrel in front of the chest; walking slows down and the shovel is put away.
function Avatar.setCarry(player)
	local rig = rigs[player]
	if not rig or rig.carrying then
		return
	end
	rig.carrying = true
	rig.token += 1
	rig.humanoid:UnequipTools()
	rig.humanoid.WalkSpeed = Config.CarryWalkSpeed
	tweenMotor(rig.motor, rig.base, 80, 0.25)
	tweenMotor(rig.leftMotor, rig.leftBase, 80, 0.25)
end

function Avatar.clearCarry(player)
	local rig = rigs[player]
	if not rig or not rig.carrying then
		return
	end
	rig.carrying = false
	rig.humanoid.WalkSpeed = rig.defaultSpeed
	tweenMotor(rig.motor, rig.base, 0, 0.25)
	tweenMotor(rig.leftMotor, rig.leftBase, 0, 0.25)
	local shovel = player.Backpack:FindFirstChild("Shovel")
	if shovel then
		rig.humanoid:EquipTool(shovel)
	end
end

function Avatar.getRoot(player)
	local rig = rigs[player]
	return rig and rig.root
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
