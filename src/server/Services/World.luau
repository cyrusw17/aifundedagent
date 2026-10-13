--!nonstrict
-- Builds the first base camp from code so it works without hand-placing anything in Studio.
local Workspace = game:GetService("Workspace")

local Gameplay = require(script.Parent.Gameplay)

local World = {}

local function newPart(parent, name, size, cframe, color, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function addPrompt(parent, actionText, objectText, holdSeconds)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = holdSeconds
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = parent
	return prompt
end

local function addSign(parent, text, offset)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(240, 50)
	gui.StudsOffset = offset
	gui.MaxDistance = 90
	gui.Parent = parent

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Parent = gui
end

local function buildBarrel(folder, position, configModule)
	local barrel = Instance.new("Part")
	barrel.Name = "HayBarrel"
	barrel.Shape = Enum.PartType.Cylinder
	barrel.Size = Vector3.new(5, 4, 4) -- cylinders run along X, so this stands it upright below
	barrel.CFrame = CFrame.new(position + Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
	barrel.Color = Color3.fromRGB(139, 90, 43)
	barrel.Material = Enum.Material.Wood
	barrel.Anchored = true
	barrel.Parent = folder

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

	local prompt = addPrompt(barrel, "Scoop hay", "Hay barrel", configModule.ScoopHoldSeconds)
	Gameplay.wireBarrel(barrel, prompt)
end

function World.build()
	local folder = Instance.new("Folder")
	folder.Name = "Needlewood"
	folder.Parent = Workspace

	local Config = require(game:GetService("ReplicatedStorage").Shared.Config.Game)

	if not Workspace:FindFirstChild("Baseplate") then
		newPart(
			folder,
			"Ground",
			Vector3.new(300, 1, 300),
			CFrame.new(0, -0.5, 0),
			Color3.fromRGB(106, 166, 90),
			Enum.Material.Grass
		)
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "BaseCampSpawn"
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.Position = Vector3.new(0, 0.5, 14)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = Color3.fromRGB(200, 180, 120)
	spawn.Parent = folder

	for i = 0, 2 do
		buildBarrel(folder, Vector3.new(-18 + i * 7, 0, -18), Config)
	end

	-- Hay shop: a simple building with a counter you walk up to.
	local shop = Instance.new("Model")
	shop.Name = "HayShop"
	shop.Parent = folder
	newPart(
		shop,
		"Floor",
		Vector3.new(16, 1, 12),
		CFrame.new(22, 0.5, -18),
		Color3.fromRGB(200, 180, 140),
		Enum.Material.WoodPlanks
	)
	newPart(shop, "BackWall", Vector3.new(16, 9, 1), CFrame.new(22, 5.5, -23.5), Color3.fromRGB(244, 239, 224))
	newPart(shop, "LeftWall", Vector3.new(1, 9, 12), CFrame.new(14.5, 5.5, -18), Color3.fromRGB(244, 239, 224))
	newPart(shop, "RightWall", Vector3.new(1, 9, 12), CFrame.new(29.5, 5.5, -18), Color3.fromRGB(244, 239, 224))
	newPart(
		shop,
		"Roof",
		Vector3.new(18, 1, 14),
		CFrame.new(22, 10.5, -18),
		Color3.fromRGB(192, 57, 43),
		Enum.Material.Slate
	)
	local counter = newPart(
		shop,
		"Counter",
		Vector3.new(10, 4, 2),
		CFrame.new(22, 3, -14),
		Color3.fromRGB(139, 90, 43),
		Enum.Material.Wood
	)
	addSign(counter, "HAY SHOP", Vector3.new(0, 6, 0))
	local prompt = addPrompt(counter, "Sell hay", "Hay shop", 0)
	Gameplay.wireShop(prompt)
end

return World
