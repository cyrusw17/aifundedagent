--!nonstrict
-- Builds the first base camp from code so it works without hand-placing anything in Studio.
local Workspace = game:GetService("Workspace")

local Bales = require(script.Parent.Bales)
local Hay = require(script.Parent.Hay)
local Tools = require(script.Parent.Tools)
local Gameplay = require(script.Parent.Gameplay)
local SellShop = require(script.Parent.SellShop)
local Props = require(script.Parent.Props)
local MeadowTerrain = require(script.Parent.MeadowTerrain)
local MeadowDecor = require(script.Parent.MeadowDecor)
local Dealer = require(script.Parent.Dealer)
local Land = require(script.Parent.Land)
local WorldLabel = require(game:GetService("ReplicatedStorage").Shared.WorldLabel)
local Bank = require(script.Parent.Bank)
local Market = require(script.Parent.Market)
local Orders = require(script.Parent.Orders)
local WorldMap = require(script.Parent.WorldMap)

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

-- Floating text goes through the shared WorldLabel helper so every sign reads the same.
local function addSign(parent, text, offset, kind)
	return WorldLabel.billboard(parent, text, { offset = offset, kind = kind or "status" })
end

function World.build()
	local folder = Instance.new("Folder")
	folder.Name = "Needlewood"
	folder.Parent = Workspace

	-- Meadow Farm's ground is scripted terrain (MeadowTerrain.luau). The template's flat baseplate would cover the
	-- pond and cut through the hills, so it goes.
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		baseplate:Destroy()
	end
	MeadowTerrain.ensure()

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "BaseCampSpawn"
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.Position = Vector3.new(0, 0.5, 14)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = Color3.fromRGB(189, 168, 112)
	spawn.Parent = folder

	Bales.init(folder)
	Hay.init(folder)
	Tools.init()
	for i = 0, 2 do
		Bales.spawn(Vector3.new(-18 + i * 7, 0, -18), true)
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
		Color3.fromRGB(128, 105, 77),
		Enum.Material.WoodPlanks
	)
	newPart(shop, "BackWall", Vector3.new(16, 9, 1), CFrame.new(22, 5.5, -23.5), Color3.fromRGB(153, 128, 97), Enum.Material.WoodPlanks)
	newPart(shop, "LeftWall", Vector3.new(1, 9, 12), CFrame.new(14.5, 5.5, -18), Color3.fromRGB(153, 128, 97), Enum.Material.WoodPlanks)
	newPart(shop, "RightWall", Vector3.new(1, 9, 12), CFrame.new(29.5, 5.5, -18), Color3.fromRGB(153, 128, 97), Enum.Material.WoodPlanks)
	newPart(
		shop,
		"Roof",
		Vector3.new(18, 1, 14),
		CFrame.new(22, 10.5, -18),
		Color3.fromRGB(102, 66, 42),
		Enum.Material.Slate
	)
	local counter = newPart(
		shop,
		"Counter",
		Vector3.new(10, 4, 2),
		CFrame.new(22, 3, -14),
		Color3.fromRGB(92, 74, 54),
		Enum.Material.Wood
	)
	addSign(counter, "HAY SHOP", Vector3.new(0, 6, 0), "sign")

	-- Sell pad in front of the counter. Walk onto it with hay, or set a bale down on it.
	local pad = newPart(
		folder,
		"SellPad",
		Vector3.new(12, 0.4, 9),
		CFrame.new(22, 0.2, -6),
		Color3.fromRGB(219, 204, 153),
		Enum.Material.Neon
	)
	pad.Transparency = 0.35
	addSign(pad, "SELL HERE", Vector3.new(0, 5, 0))
	Gameplay.wireSellPad(pad)

	-- Today's needle prices on this server (Market.luau), on a board beside the sell pad.
	Market.build(folder, Vector3.new(34, 0, -8))

	-- NPC buyer orders and their delivery pad, on the west side of camp (Orders.luau).
	Orders.build(folder, Vector3.new(-34, 0, 6))

	-- Bale drop-off between the bales and the shop. Bales set down here stay until you smash or sell them.
	local dropOff = newPart(
		folder,
		"BaleDropOff",
		Vector3.new(14, 0.2, 10),
		CFrame.new(0, 0.1, -4),
		Color3.fromRGB(92, 74, 54),
		Enum.Material.WoodPlanks
	)
	addSign(dropOff, "BALE DROP-OFF", Vector3.new(0, 5, 0))
	Bales.setDropOff(dropOff)

	-- The Rustic props that have no job yet (wheelbarrow, crate, logs, spare tools) dress up the camp.
	Props.dressBaseCamp(folder)

	-- The public hay sell shop with its conveyor line, east of base camp.
	SellShop.build(folder)

	-- The truck dealer west of camp, then bales, trees and signs over the rest of the meadow.
	Dealer.build(folder)
	MeadowDecor.build(folder)

	-- The land office and the buildable plots south of the main road.
	Land.build(folder)

	-- Meadow Savings & Loan, on the main road east of the plot road.
	Bank.build(folder)

	-- The rest of the Stitched Isles around Meadow: every region, the highway, the ferries and the zeppelin.
	WorldMap.build(folder)
end

return World
