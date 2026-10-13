--!nonstrict
-- What the player looks like while working: the shovel and rake, their swings, and the carry pose.
-- Tools use the Rustic Blender meshes once they are imported (see Props.luau) and fall back to parts until then.
-- Each swing only plays with its own tool equipped.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config.Game)
local GloveConfig = require(ReplicatedStorage.Shared.Config.Gloves)
local Groups = require(script.Parent.Groups)
local Props = require(script.Parent.Props)
local PropsConfig = require(ReplicatedStorage.Shared.Config.Props)
local Data = require(script.Parent.Data)
local Gloves = require(script.Parent.Gloves)

local Avatar = {}

Avatar.onToolActivated = nil -- set by Tools.init: function(player, kind) for each click with a tool

local rigs = {}

local WOOD = Color3.fromRGB(128, 105, 77) -- rustic weathered handle

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

-- Gives a part-built tool the Rustic Blender prop's look when it was imported. The part tool stays as the fallback,
-- shown until the mesh has loaded on each client (see Props.weldTo). The prop keeps its true Blender size (a small
-- shovel, as Cyrus asked) and is turned blade-up (it is modeled blade-down) so the blade leads like the part tools,
-- with the end of its handle just below the hand.
local function addMesh(tool, prop)
	local handle = tool.Handle
	local length = PropsConfig.Sizes[prop]
	local center = CFrame.new(0, length / 2 - PropsConfig.GripFromEnd, 0)
	local model = Props.make(prop, handle.CFrame * center, length, CFrame.Angles(0, 0, math.pi))
	if model then
		Props.weldTo(model, handle, tool)
	elseif Props.has(prop) then
		warn(("[Needlewood] %s mesh was found but could not be copied, so the %s uses parts"):format(prop, tool.Name))
	end
	return tool
end

-- The shaft and blade point out of the top of the handle, so the blade leads when the arm reaches forward.
local function buildShovel()
	local tip = "Face a bale to smash it, or a pile to scoop it, and click."
	return addMesh(buildTool("Shovel", tip, {
		-- A small hand spade matching the Blender basic_shovel at true size: blade tip at y 2.1, blade from 1.4 up.
		-- Its reach comes from Config ShovelReach/ToolReach, not from its length.
		{ "Shaft", Vector3.new(0.3, 0.6, 0.3), CFrame.new(0, 1.1, 0), WOOD, Enum.Material.Wood },
		{
			"Blade",
			Vector3.new(0.6, 0.7, 0.12),
			CFrame.new(0, 1.75, 0),
			Color3.fromRGB(128, 117, 105),
			Enum.Material.Metal,
		},
	}), "basic_shovel")
end

-- A long shaft with a crossbar and a row of teeth at the end.
local function buildRake()
	local tip = "Face loose hay and click to drag it toward you."
	local steel = Color3.fromRGB(107, 94, 84)
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
	return addMesh(buildTool("Rake", tip, parts), "garden_rake")
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
	-- Some rigs lock the shoulder joint (Studio reports C0 as read only). The arm pose is only cosmetic, so if it
	-- cannot move, skip it rather than let the error stop the swing, the scoop or the carry.
	local goal = { C0 = base * CFrame.Angles(math.rad(degrees), 0, 0) }
	local info = TweenInfo.new(seconds, style or Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	local ok = pcall(function()
		TweenService:Create(motor, info, goal):Play()
	end)
	if not ok then
		pcall(function()
			motor.C0 = goal.C0
		end)
	end
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

	-- Hay in your arms or a bale on your shoulder slows you down; see Gloves.walkSpeed.
	Avatar.refreshSpeed(player)

	-- No shovel while carrying a bale.
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

	local backpack = player:WaitForChild("Backpack", 10)
	if not backpack then
		warn(("[Needlewood] %s has no Backpack, so no shovel or rake was given"):format(player.Name))
		return
	end
	local shovel = hook(buildShovel())
	shovel.Parent = backpack
	hook(buildRake()).Parent = backpack
	humanoid:EquipTool(shovel)

	-- Tools fail quietly when they do, so say in the log where one was lost.
	task.delay(1, function()
		if not character.Parent or rig.carrying then
			return
		end
		if shovel.Parent ~= character and shovel.Parent ~= backpack then
			warn(("[Needlewood] %s's shovel left their backpack (now in %s)"):format(player.Name, shovel:GetFullName()))
		elseif shovel.Parent ~= character and not character:FindFirstChildOfClass("Tool") then
			warn(("[Needlewood] %s's shovel did not equip"):format(player.Name))
		end
		local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
		if shovel.Parent == character and hand and not hand:FindFirstChild("RightGrip") then
			warn(("[Needlewood] %s holds the shovel but no RightGrip joins it to the hand"):format(player.Name))
		end
	end)
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

-- Both arms hold a bale in front of the chest; walking slows down and the shovel is put away.
function Avatar.setCarry(player)
	local rig = rigs[player]
	if not rig or rig.carrying then
		return
	end
	rig.carrying = true
	rig.token += 1
	rig.humanoid:UnequipTools()
	Avatar.refreshSpeed(player)
	tweenMotor(rig.motor, rig.base, 80, 0.25)
	tweenMotor(rig.leftMotor, rig.leftBase, 80, 0.25)
end

function Avatar.clearCarry(player)
	local rig = rigs[player]
	if not rig or not rig.carrying then
		return
	end
	rig.carrying = false
	Avatar.refreshSpeed(player)
	tweenMotor(rig.motor, rig.base, 0, 0.25)
	tweenMotor(rig.leftMotor, rig.leftBase, 0, 0.25)
	local shovel = player.Backpack:FindFirstChild("Shovel")
	if shovel then
		rig.humanoid:EquipTool(shovel)
	end
end

-- Walk speed from what the player is carrying: loose hay (state.loadWeight, kept by Tools) plus any bale, eased by
-- their gloves. Runs whenever the load, the bale or the gloves change.
function Avatar.refreshSpeed(player)
	local rig = rigs[player]
	local state = Data.get(player)
	if not rig or not rig.humanoid.Parent then
		return
	end
	local weight, tier = 0, 0
	if state then
		if state.loadHay <= 0 then
			state.loadWeight, state.loadTier = 0, 0
		end
		weight = state.loadWeight or state.loadHay
		tier = state.loadTier or 0
		-- Bales in a wheelbarrow weigh a fraction of their weight: the wheel takes most of it.
		for _, bale in state.barrow or {} do
			local baleWeight, baleTier = Gloves.baleWeight(bale.body)
			weight += baleWeight * Config.WheelbarrowLoadFactor
			tier = math.max(tier, baleTier)
		end
		if state.carryBale and state.carryBale.body then
			local baleWeight, baleTier = Gloves.baleWeight(state.carryBale.body)
			weight += baleWeight
			tier = math.max(tier, baleTier)
		end
	end
	local speed = Gloves.walkSpeed(player, rig.defaultSpeed, weight, tier)
	rig.humanoid.WalkSpeed = speed
	-- How hard the load is on you, 0 (easy) to 1 (crawling), for the client's camera bob and stagger.
	local range = math.max(rig.defaultSpeed - GloveConfig.MinWalkSpeed, 1)
	player:SetAttribute("Strain", math.clamp((rig.defaultSpeed - speed) / range, 0, 1))
	player:SetAttribute("UnderGeared", weight > 0 and Gloves.shortBy(player, tier) > 0)
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

	-- Selling, scooping and gloves all end in an attribute change, so speed follows them.
	Gloves.changed = Avatar.refreshSpeed
	local function watchLoad(player)
		player:GetAttributeChangedSignal("LoadHay"):Connect(function()
			Avatar.refreshSpeed(player)
		end)
	end
	Players.PlayerAdded:Connect(watchLoad)
	for _, player in Players:GetPlayers() do
		watchLoad(player)
	end
end

return Avatar
