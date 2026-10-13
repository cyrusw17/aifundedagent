--!nonstrict
-- Builds the first base camp from code so it works without hand-placing anything in Studio.
local Workspace = game:GetService("Workspace")

local Barrels = require(script.Parent.Barrels)
local Hay = require(script.Parent.Hay)
local Tools = require(script.Parent.Tools)
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

function World.build()
	local folder = Instance.new("Folder")
	folder.Name = "Needlewood"
	folder.Parent = Workspace

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

	Barrels.init(folder)
	Hay.init(folder)
	Tools.init()
	for i = 0, 2 do
		Barrels.spawn(Vector3.new(-18 + i * 7, 0, -18), true)
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

	-- Sell pad in front of the counter. Walk onto it with hay, or set a barrel down on it.
	local pad = newPart(
		folder,
		"SellPad",
		Vector3.new(12, 0.4, 9),
		CFrame.new(22, 0.2, -6),
		Color3.fromRGB(240, 173, 46),
		Enum.Material.Neon
	)
	pad.Transparency = 0.35
	addSign(pad, "SELL HERE", Vector3.new(0, 5, 0))
	Gameplay.wireSellPad(pad)

	-- Barrel drop-off between the barrels and the shop. Barrels set down here stay until you smash or sell them.
	local dropOff = newPart(
		folder,
		"BarrelDropOff",
		Vector3.new(14, 0.2, 10),
		CFrame.new(0, 0.1, -4),
		Color3.fromRGB(150, 110, 70),
		Enum.Material.WoodPlanks
	)
	addSign(dropOff, "BARREL DROP-OFF", Vector3.new(0, 5, 0))
	Barrels.setDropOff(dropOff)
end

return World
