--!nonstrict
-- The goal bar, the MAP / SHOP / BOOK / HELP / settings buttons under the HUD, the map screen, the shop page and the "+$63" pops.
-- Nothing here buys anything: the shop shows prices and points you to the counter that sells each thing.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = Shared:WaitForChild("UI")
local Config = Shared:WaitForChild("Config")
local Kit = require(UI:WaitForChild("Kit"))
local Menus = require(UI:WaitForChild("Menus"))
local Waypoint = require(UI:WaitForChild("Waypoint"))
local Places = require(UI:WaitForChild("Places"))
local Catalog = require(UI:WaitForChild("Catalog"))
local Hud = require(UI:WaitForChild("Hud"))
local DiscoveryList = require(UI:WaitForChild("DiscoveryList"))
local Meadow = require(Config:WaitForChild("Meadow"))
local LandConfig = require(Config:WaitForChild("Land"))
local Rustic = require(Config:WaitForChild("Rustic"))
local GameConfig = require(Config:WaitForChild("Game"))
local Prices = require(Config:WaitForChild("Prices"))

local Theme = Kit.Theme
local C, F, T = Theme.Colors, Theme.Fonts, Theme.Text
local player = Players.LocalPlayer

local gui = Kit.screen("NeedlewoodMenus", 5)

-- Goal bar ---------------------------------------------------------------------------------------------------------
-- Sits in the HUD column (UI/Hud.luau) under the cash card and the bank line.

local goal = Instance.new("Frame")
goal.Name = "GoalBar"
goal.LayoutOrder = Hud.Order.Goal
goal.Size = UDim2.fromOffset(230, 54)
goal.BackgroundColor3 = C.Wood
goal.BackgroundTransparency = 0.1
goal.Parent = Hud.column()
Kit.corner(goal, 10)
Kit.stroke(goal, C.Ink, 1.5)
local goalTitle = Kit.label(goal, "", { size = T.Small, font = F.Bold, color = C.Cream, wrap = false })
goalTitle.Position = UDim2.fromOffset(10, 4)
goalTitle.Size = UDim2.new(1, -20, 0, 18)
goalTitle.TextTruncate = Enum.TextTruncate.AtEnd
local goalBack = Instance.new("Frame")
goalBack.Position = UDim2.fromOffset(10, 25)
goalBack.Size = UDim2.new(1, -20, 0, 8)
goalBack.BackgroundColor3 = C.Ink
goalBack.BorderSizePixel = 0
goalBack.Parent = goal
Kit.corner(goalBack, 4)
local goalFill = Instance.new("Frame")
goalFill.Size = UDim2.fromScale(0, 1)
goalFill.BackgroundColor3 = C.Hay
goalFill.BorderSizePixel = 0
goalFill.Parent = goalBack
Kit.corner(goalFill, 4)
local goalMoney = Kit.label(goal, "", { size = T.Small, font = F.Medium, color = C.Cream, wrap = false })
goalMoney.Position = UDim2.fromOffset(10, 34)
goalMoney.Size = UDim2.new(1, -20, 0, 16)
local goalButton = Instance.new("TextButton")
goalButton.Size = UDim2.fromScale(1, 1)
goalButton.BackgroundTransparency = 1
goalButton.Text = ""
goalButton.Parent = goal

local currentGoal = nil
local function refreshGoal()
	currentGoal = Catalog.nextGoal()
	goal.Visible = player:GetAttribute("SaveSlot") ~= nil
	if not currentGoal then
		goalTitle.Text = "Every goal done. Nice farm!"
		goalMoney.Text = ""
		goalFill.Size = UDim2.fromScale(1, 1)
		return
	end
	local cash = player:GetAttribute("Cash") or 0
	goalTitle.Text = "NEXT: " .. currentGoal.name
	-- Trucks are meant to be bought on a bank loan, so for those the bar fills toward the down payment.
	local target = currentGoal.price
	local down = currentGoal.loan and math.floor(currentGoal.price * (Prices.Bank.DownPayment or 1)) or nil
	if down and cash < down then
		target = down
	end
	goalFill.Size = UDim2.fromScale(math.clamp(cash / math.max(target, 1), 0, 1), 1)
	if GameConfig.InfiniteMoney then
		goalMoney.Text = ("%s  ·  test cash is on"):format(Kit.money(currentGoal.price))
	elseif cash >= currentGoal.price then
		goalMoney.Text = ("%s  ·  you can buy it now!"):format(Kit.money(currentGoal.price))
	elseif down and cash >= down then
		goalMoney.Text = ("%s  ·  bank loan ready"):format(Kit.money(currentGoal.price))
	elseif down then
		goalMoney.Text = ("%s / %s down"):format(Kit.money(cash), Kit.money(down))
	else
		goalMoney.Text = ("%s / %s"):format(Kit.money(cash), Kit.money(currentGoal.price))
	end
end
goalButton.Activated:Connect(function()
	if currentGoal and currentGoal.place then
		Waypoint.set(Places.get(currentGoal.place), Places.name(currentGoal.place))
	end
end)
for _, name in
	{ "Cash", "OwnedTrucks", "OwnedTrailers", "Gear", "GlovesOwned", "LandPlot", "TutorialFlags", "SaveSlot" }
do
	player:GetAttributeChangedSignal(name):Connect(refreshGoal)
end
refreshGoal()

-- Menu buttons -----------------------------------------------------------------------------------------------------

local rail = Instance.new("Frame")
rail.LayoutOrder = Hud.Order.Buttons
rail.Size = UDim2.fromOffset(230, 36)
rail.BackgroundTransparency = 1
rail.Parent = Hud.column()
local railLayout = Instance.new("UIListLayout")
railLayout.FillDirection = Enum.FillDirection.Horizontal
railLayout.Padding = UDim.new(0, 5)
railLayout.SortOrder = Enum.SortOrder.LayoutOrder
railLayout.Parent = rail
local railButtons = {}
-- Hotkeys are listed in Settings > Controls; the buttons stay short so five fit a phone-width column.
for i, def in { { "MAP", "Map" }, { "SHOP", "Shop" }, { "BOOK", "Book" }, { "HELP", "Help" }, { "⚙", "Settings" } } do
	local b = Kit.button(rail, def[1], "wood", UDim2.fromOffset(42, 34))
	b.LayoutOrder = i
	b.TextSize = T.Small
	railButtons[def[2]] = b
	b.Activated:Connect(function()
		if def[2] == "Help" then
			Menus.close()
			Menus.event("Help"):Fire()
		else
			Menus.toggle(def[2])
		end
	end)
end
Menus.changed.Event:Connect(function(name)
	for key, b in railButtons do
		Kit.setStyle(b, key == name and "picked" or "wood")
	end
end)

local function showRail()
	rail.Visible = player:GetAttribute("SaveSlot") ~= nil
end
player:GetAttributeChangedSignal("SaveSlot"):Connect(showRail)
showRail()

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or not player:GetAttribute("SaveSlot") then
		return
	end
	if input.KeyCode == Enum.KeyCode.M and not player:GetAttribute("Building") then
		Menus.toggle("Map")
	elseif input.KeyCode == Enum.KeyCode.B then
		Menus.toggle("Shop")
	elseif input.KeyCode == Enum.KeyCode.K then
		Menus.toggle("Book")
	elseif input.KeyCode == Enum.KeyCode.Escape then
		Menus.close()
	end
end)

-- Earnings pops ----------------------------------------------------------------------------------------------------

local popCount = 0
local function pop(amount)
	popCount += 1
	local slot = popCount % 3
	local label = Kit.label(gui, "+" .. Kit.money(amount), { size = 24, font = F.Title, color = C.Cash, wrap = false })
	label.Size = UDim2.fromOffset(160, 30)
	label.Position = UDim2.fromOffset(252, 18 + slot * 10)
	label.TextStrokeColor3 = C.Ink
	label.TextStrokeTransparency = 0.1
	local info = TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(label, info, {
		Position = label.Position - UDim2.fromOffset(0, 28),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	task.delay(1.5, function()
		label:Destroy()
	end)
end
task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("Tutorial")
	remotes:WaitForChild("Earned").OnClientEvent:Connect(pop)
end)

-- Map --------------------------------------------------------------------------------------------------------------

local MAP_W, MAP_H = 720, 540
local CANVAS = 470
local HALF = Meadow.HalfSize
local SCALE = CANVAS / (HALF * 2)

local mapPanel, mapBody = Kit.panel(gui, {
	name = "Map",
	title = "MAP  ·  MEADOW FARM",
	width = MAP_W,
	height = MAP_H,
	onClose = function()
		Menus.close()
	end,
})

local canvas = Instance.new("TextButton")
canvas.Name = "Canvas"
canvas.Text = ""
canvas.AutoButtonColor = false
canvas.Size = UDim2.fromOffset(CANVAS, CANVAS)
canvas.BackgroundColor3 = Rustic.Grass
canvas.ClipsDescendants = true
canvas.Parent = mapBody
Kit.corner(canvas, 6)
Kit.stroke(canvas, C.Ink, 2)

local function toMap(x, z)
	return UDim2.fromOffset((x + HALF) * SCALE, (z + HALF) * SCALE)
end

local function rect(parent, min, max, color, z)
	local f = Instance.new("Frame")
	f.Position = toMap(min.X, min.Y)
	f.Size = UDim2.fromOffset((max.X - min.X) * SCALE, (max.Y - min.Y) * SCALE)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.ZIndex = z or 2
	f.Parent = parent
	return f
end

-- The hills at the edge of the biome, then the roads, the pond and the buildings.
local edge = HALF - Meadow.EdgeStart
for _, r in
	{
		{ Vector2.new(-HALF, -HALF), Vector2.new(HALF, -HALF + edge) },
		{ Vector2.new(-HALF, HALF - edge), Vector2.new(HALF, HALF) },
		{ Vector2.new(-HALF, -HALF), Vector2.new(-HALF + edge, HALF) },
		{ Vector2.new(HALF - edge, -HALF), Vector2.new(HALF, HALF) },
	}
do
	rect(canvas, r[1], r[2], Rustic.LeafyGrass, 1).BackgroundTransparency = 0.2
end

for _, road in Meadow.Roads do
	for i = 1, #road.points - 1 do
		local a, b = road.points[i], road.points[i + 1]
		local mid = (a + b) / 2
		local d = b - a
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = toMap(mid.X, mid.Y)
		f.Size = UDim2.fromOffset((d.Magnitude + Meadow.RoadWidth) * SCALE, Meadow.RoadWidth * SCALE)
		f.Rotation = math.deg(math.atan2(d.Y, d.X))
		f.BackgroundColor3 = Rustic.Dirt
		f.BorderSizePixel = 0
		f.ZIndex = 2
		f.Parent = canvas
	end
end

do
	local pond = Meadow.Pond
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = toMap(pond.center.X, pond.center.Y)
	f.Size = UDim2.fromOffset(pond.radius * 2 * SCALE, pond.radius * 2 * SCALE)
	f.BackgroundColor3 = Rustic.Water
	f.BorderSizePixel = 0
	f.ZIndex = 2
	f.Parent = canvas
	Kit.corner(f, 999)
end

local function smallText(parent, text, position, color, z)
	local l =
		Kit.label(parent, text, { size = 11, font = F.Bold, color = color or C.Cream, align = "center", wrap = false })
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Position = position
	l.Size = UDim2.fromOffset(140, 14)
	l.TextStrokeColor3 = C.Ink
	l.TextStrokeTransparency = 0.2
	l.ZIndex = z or 6
	return l
end

-- Buildings
local DEALER = Meadow.DealerCenter
rect(canvas, Vector2.new(DEALER.X - 30, DEALER.Z - 26), Vector2.new(DEALER.X + 30, DEALER.Z + 26), Rustic.PaintRed, 3)
rect(canvas, Meadow.LandOffice.min, Meadow.LandOffice.max, Rustic.WoodDark, 3)
rect(canvas, Vector2.new(14, -24), Vector2.new(30, -12), Rustic.WoodDark, 3) -- hay shop
rect(canvas, Vector2.new(48, -40), Vector2.new(96, -10), Rustic.Stone, 3) -- HAY SELL SHOP slab and belts
for _, zone in Meadow.Flat do
	if zone.name == "Bank" then
		rect(canvas, zone.min, zone.max, Rustic.StoneDark, 3) -- Meadow Savings & Loan
	end
end

-- Plots, colored by owner.
local plotFrames = {}
for index, def in LandConfig.Plots do
	for _, zone in Meadow.Plots do
		if zone.id == def.zone then
			local f = rect(canvas, zone.min, zone.max, Rustic.Hay, 3)
			f.BackgroundTransparency = 0.35
			Kit.stroke(f, C.Ink, 1).Transparency = 0.4
			local center = (zone.min + zone.max) / 2
			plotFrames[index] =
				{ frame = f, label = smallText(canvas, def.name, toMap(center.X, center.Y), C.Cream, 5) }
		end
	end
end

local function refreshPlots()
	local mine = player:GetAttribute("LandPlot") or 0
	local state = ReplicatedStorage:FindFirstChild("Land")
	local owners = {}
	for _, info in state and state:GetChildren() or {} do
		if info:IsA("Configuration") then
			owners[info:GetAttribute("Index")] = info:GetAttribute("OwnerId") or 0
		end
	end
	for index, p in plotFrames do
		local def = LandConfig.Plots[index]
		if index == mine then
			p.frame.BackgroundColor3 = C.Green
			p.label.Text = def.name .. " (yours)"
		elseif (owners[index] or 0) ~= 0 then
			p.frame.BackgroundColor3 = C.Muted
			p.label.Text = def.name
		else
			p.frame.BackgroundColor3 = Rustic.Hay
			p.label.Text = ("%s  %s"):format(def.name, Kit.money(def.price))
		end
	end
end

-- Road gates to the next regions.
for _, gate in Meadow.Gates do
	local text = gate.text:gsub("\n", " "):gsub("COMING SOON", "(soon)")
	local at = gate.at + gate.facing * 30
	smallText(canvas, text, toMap(at.X, at.Y), C.Cream, 6)
end

-- Landmarks you can click for a waypoint.
local landmarkButtons = {}
for _, place in Places.List do
	local dot = Instance.new("TextButton")
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Size = UDim2.fromOffset(12, 12)
	dot.BackgroundColor3 = C.Cream
	dot.Text = ""
	dot.ZIndex = 7
	dot.Parent = canvas
	Kit.corner(dot, 999)
	Kit.stroke(dot, C.Ink, 1.5)
	local label = smallText(canvas, place.name, UDim2.new(), C.Cream, 7)
	dot.Activated:Connect(function()
		Waypoint.set(Places.get(place.id), place.name)
	end)
	landmarkButtons[place.id] = { dot = dot, label = label }
end

local function placeLandmarks()
	for id, b in landmarkButtons do
		local p = Places.get(id)
		if p then
			b.dot.Position = toMap(p.X, p.Z)
			b.label.Position = toMap(p.X, p.Z) + UDim2.fromOffset(0, -12)
		end
	end
end

-- You, your trucks and the waypoint.
local me = Kit.label(canvas, "▲", { size = 20, font = F.Title, color = C.Red, align = "center", wrap = false })
me.AnchorPoint = Vector2.new(0.5, 0.5)
me.Size = UDim2.fromOffset(22, 22)
me.TextStrokeColor3 = C.Cream
me.TextStrokeTransparency = 0
me.ZIndex = 9

local marker = Kit.label(canvas, "✕", { size = 18, font = F.Title, color = C.Red, align = "center", wrap = false })
marker.AnchorPoint = Vector2.new(0.5, 0.5)
marker.Size = UDim2.fromOffset(20, 20)
marker.TextStrokeColor3 = C.Cream
marker.TextStrokeTransparency = 0
marker.ZIndex = 8
marker.Visible = false
Waypoint.changed.Event:Connect(function(position)
	marker.Visible = position ~= nil
	if position then
		marker.Position = toMap(position.X, position.Z)
	end
end)

-- Truck models, found once and then as they arrive (scanning the whole world every second stutters on phones).
local trucks = {}
local function noteTruck(d)
	if d:IsA("Model") and d:GetAttribute("TruckId") then
		trucks[d] = true
	end
end
for _, d in Workspace:GetDescendants() do
	noteTruck(d)
end
Workspace.DescendantAdded:Connect(noteTruck)
Workspace.DescendantRemoving:Connect(function(d)
	trucks[d] = nil
end)

local truckDots = {}
local function refreshTrucks()
	for _, d in truckDots do
		d:Destroy()
	end
	table.clear(truckDots)
	for model in trucks do
		if model.Parent and model:GetAttribute("OwnerId") == player.UserId then
			local p = model:GetPivot().Position
			local d =
				Kit.label(canvas, "TRUCK", { size = 10, font = F.Bold, color = C.Ink, align = "center", wrap = false })
			d.AnchorPoint = Vector2.new(0.5, 0.5)
			d.Size = UDim2.fromOffset(40, 14)
			d.Position = toMap(p.X, p.Z)
			d.BackgroundTransparency = 0
			d.BackgroundColor3 = C.Cream
			d.ZIndex = 8
			Kit.corner(d, 4)
			table.insert(truckDots, d)
		end
	end
end

-- Click anywhere on the map for a waypoint there.
canvas.InputBegan:Connect(function(input)
	local kind = input.UserInputType
	if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then
		return
	end
	local frac = (Vector2.new(input.Position.X, input.Position.Y) - canvas.AbsolutePosition) / canvas.AbsoluteSize
	if frac.X < 0 or frac.Y < 0 or frac.X > 1 or frac.Y > 1 then
		return
	end
	local x, z = frac.X * HALF * 2 - HALF, frac.Y * HALF * 2 - HALF
	Waypoint.set(Vector3.new(x, 0, z), "Marked spot")
end)

-- World view: every region of the Stitched Isles from Config/WorldMap ("Full world map build"), when it is there.
local WorldMap = nil
do
	local module = Config:FindFirstChild("WorldMap")
	if module then
		local ok, result = pcall(require, module)
		if ok and typeof(result) == "table" and result.Regions and result.Bounds then
			WorldMap = result
		end
	end
end

local worldCanvas = nil
local weatherLabels = {} -- region id -> label under its name on the WORLD map
local worldEvent = nil
local stamps = {} -- discovery id -> its stamp on the WORLD map
local worldMe = nil
local worldMarker = nil
local worldRich = nil
local toWorld = nil

-- The region a world position is in (same rules as RegionBanner.client.luau).
local function regionAt(position)
	if not WorldMap then
		return "Meadow Farm"
	end
	local sky = WorldMap.SkyIsland
	if
		sky
		and position.Y > sky.top - 60
		and (Vector2.new(position.X, position.Z) - sky.center).Magnitude < sky.radius + 40
	then
		return "Sky Island"
	end
	local cave = WorldMap.Cave and WorldMap.Cave.chamber
	if cave and (position - cave.center).Magnitude < cave.radius * 1.2 then
		return "Crystal Cave"
	end
	if math.abs(position.X) < HALF and math.abs(position.Z) < HALF then
		return "Meadow Farm"
	end
	local best, bestValue = nil, 0
	for _, r in WorldMap.Regions do
		local dx = (position.X - r.center.X) / r.radius.X
		local dz = (position.Z - r.center.Y) / r.radius.Y
		local value = 1 - math.sqrt(dx * dx + dz * dz)
		if value > bestValue then
			best, bestValue = r.name, value
		end
	end
	return best or "Open sea"
end

if WorldMap then
	local bmin, bmax = WorldMap.Bounds.min, WorldMap.Bounds.max
	local span = bmax - bmin
	local wscale = CANVAS / math.max(span.X, span.Y)
	local offsetY = (CANVAS - span.Y * wscale) / 2
	toWorld = function(x, z)
		return UDim2.fromOffset((x - bmin.X) * wscale, (z - bmin.Y) * wscale + offsetY)
	end

	worldCanvas = Instance.new("TextButton")
	worldCanvas.Name = "WorldCanvas"
	worldCanvas.Text = ""
	worldCanvas.AutoButtonColor = false
	worldCanvas.Size = UDim2.fromOffset(CANVAS, CANVAS)
	worldCanvas.BackgroundColor3 = Rustic.Water
	worldCanvas.ClipsDescendants = true
	worldCanvas.Visible = false
	worldCanvas.Parent = mapBody
	Kit.corner(worldCanvas, 6)
	Kit.stroke(worldCanvas, C.Ink, 2)

	local MATERIAL = {
		LeafyGrass = Rustic.LeafyGrass,
		Grass = Rustic.Grass,
		Mud = Rustic.Mud,
		Sand = Rustic.Sand,
		Rock = Rustic.Rock,
		Ground = Rustic.Dirt,
	}
	local function colorOf(region)
		local top = region.materials and region.materials.top
		return MATERIAL[top] or (WorldMap.Colors and WorldMap.Colors[top]) or Rustic.Grass
	end

	local function oval(center, radius, color, z)
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = toWorld(center.X, center.Y)
		f.Size = UDim2.fromOffset(radius.X * 2 * wscale, radius.Y * 2 * wscale)
		f.BackgroundColor3 = color
		f.BorderSizePixel = 0
		f.ZIndex = z or 2
		f.Parent = worldCanvas
		Kit.corner(f, 999)
		return f
	end

	local function line(a, b, width, color, z)
		local mid = (a + b) / 2
		local d = b - a
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = toWorld(mid.X, mid.Y)
		f.Size = UDim2.fromOffset(d.Magnitude * wscale, math.max(width * wscale, 2))
		f.Rotation = math.deg(math.atan2(d.Y, d.X))
		f.BackgroundColor3 = color
		f.BorderSizePixel = 0
		f.ZIndex = z or 4
		f.Parent = worldCanvas
		return f
	end

	for _, region in WorldMap.Regions do
		oval(region.center, region.radius, colorOf(region), 2)
	end
	-- Meadow Farm itself, the square in the middle.
	local meadow = Instance.new("Frame")
	meadow.Position = toWorld(-HALF, -HALF)
	meadow.Size = UDim2.fromOffset(HALF * 2 * wscale, HALF * 2 * wscale)
	meadow.BackgroundColor3 = Rustic.Grass
	meadow.BorderSizePixel = 0
	meadow.ZIndex = 3
	meadow.Parent = worldCanvas
	if WorldMap.SkyIsland then
		local sky = oval(
			WorldMap.SkyIsland.center,
			Vector2.new(WorldMap.SkyIsland.radius, WorldMap.SkyIsland.radius),
			C.Cream,
			5
		)
		sky.BackgroundTransparency = 0.45
	end

	for _, road in WorldMap.Roads or {} do
		for i = 1, #road.points - 1 do
			line(road.points[i], road.points[i + 1], WorldMap.RoadWidth or 16, Rustic.Dirt, 4)
		end
	end
	for _, road in Meadow.Roads do
		for i = 1, #road.points - 1 do
			line(road.points[i], road.points[i + 1], Meadow.RoadWidth, Rustic.Dirt, 4)
		end
	end
	if WorldMap.Highway then
		line(WorldMap.Highway.from, WorldMap.Highway.to, WorldMap.Highway.width or 22, Rustic.StoneDark, 4)
	end
	for _, route in WorldMap.Ferry and WorldMap.Ferry.Routes or {} do
		local f = line(route.a.pierEnd, route.b.pierEnd, 8, C.Cream, 4)
		f.BackgroundTransparency = 0.3
	end
	if WorldMap.Zeppelin then
		local a, b = WorldMap.Zeppelin.a.pos, WorldMap.Zeppelin.b.pos
		local f = line(Vector2.new(a.X, a.Z), Vector2.new(b.X, b.Z), 8, C.Cream, 6)
		f.BackgroundTransparency = 0.3
	end

	local function worldText(text, at, size, z)
		local l = Kit.label(
			worldCanvas,
			text,
			{ size = size or 10, font = F.Bold, color = C.Cream, align = "center", wrap = false }
		)
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.Position = toWorld(at.X, at.Y)
		l.Size = UDim2.fromOffset(120, 14)
		l.TextStrokeColor3 = C.Ink
		l.TextStrokeTransparency = 0.2
		l.ZIndex = z or 7
		return l
	end
	for _, region in WorldMap.Regions do
		worldText(region.name, region.center, 10)
		weatherLabels[region.id] = worldText("", region.center, 10)
		weatherLabels[region.id].Position += UDim2.fromOffset(0, 13)
	end
	worldText("Meadow Farm", Vector2.new(0, 0), 11)
	weatherLabels.meadow = worldText("", Vector2.new(0, 0), 10)
	weatherLabels.meadow.Position += UDim2.fromOffset(0, 14)
	if WorldMap.SkyIsland then
		worldText("Sky Island", WorldMap.SkyIsland.center + Vector2.new(0, -WorldMap.SkyIsland.radius - 60), 10)
	end

	worldMe =
		Kit.label(worldCanvas, "▲", { size = 16, font = F.Title, color = C.Red, align = "center", wrap = false })
	worldMe.AnchorPoint = Vector2.new(0.5, 0.5)
	worldMe.Size = UDim2.fromOffset(18, 18)
	worldMe.TextStrokeColor3 = C.Cream
	worldMe.TextStrokeTransparency = 0
	worldMe.ZIndex = 9

	worldMarker =
		Kit.label(worldCanvas, "✕", { size = 14, font = F.Title, color = C.Red, align = "center", wrap = false })
	worldMarker.AnchorPoint = Vector2.new(0.5, 0.5)
	worldMarker.Size = UDim2.fromOffset(16, 16)
	worldMarker.TextStrokeColor3 = C.Cream
	worldMarker.TextStrokeTransparency = 0
	worldMarker.ZIndex = 8
	worldMarker.Visible = false

	-- The rich field (2x needles), moved by the server every 20 minutes.
	worldRich =
		Kit.label(worldCanvas, "★ 2x", { size = 11, font = F.Title, color = C.Hay, align = "center", wrap = false })
	worldRich.AnchorPoint = Vector2.new(0.5, 0.5)
	worldRich.Size = UDim2.fromOffset(40, 14)
	worldRich.TextStrokeColor3 = C.Ink
	worldRich.TextStrokeTransparency = 0
	worldRich.ZIndex = 8

	-- Discovery stamps: a gold ◆ on each landmark you have found, a ✓ above each region you have visited.
	for _, d in DiscoveryList.all() do
		local stamp = Kit.label(worldCanvas, d.kind == "region" and "✓" or "◆", {
			size = d.kind == "region" and 12 or 11,
			font = F.Title,
			color = C.Hay,
			align = "center",
			wrap = false,
		})
		stamp.AnchorPoint = Vector2.new(0.5, 0.5)
		stamp.Size = UDim2.fromOffset(14, 14)
		stamp.Position = toWorld(d.at.X, d.at.Y)
		if d.kind == "region" then
			stamp.Position += UDim2.fromOffset(0, -13)
		end
		stamp.TextStrokeColor3 = C.Ink
		stamp.TextStrokeTransparency = 0
		stamp.ZIndex = 8
		stamp.Visible = false
		stamps[d.id] = stamp
	end

	-- A region event (Hay Fever, Sandstorm...) while one runs.
	worldEvent =
		Kit.label(worldCanvas, "", { size = 11, font = F.Title, color = C.Cream, align = "center", wrap = false })
	worldEvent.AnchorPoint = Vector2.new(0.5, 0.5)
	worldEvent.Size = UDim2.fromOffset(0, 18)
	worldEvent.AutomaticSize = Enum.AutomaticSize.X
	worldEvent.BackgroundColor3 = C.Red
	worldEvent.BackgroundTransparency = 0.1
	worldEvent.ZIndex = 9
	worldEvent.Visible = false
	Kit.corner(worldEvent, 6)
	Kit.pad(worldEvent, 4)

	worldCanvas.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then
			return
		end
		local local2 = (Vector2.new(input.Position.X, input.Position.Y) - worldCanvas.AbsolutePosition)
			/ worldCanvas.AbsoluteSize
			* CANVAS
		local x = local2.X / wscale + bmin.X
		local z = (local2.Y - offsetY) / wscale + bmin.Y
		if x < bmin.X or x > bmax.X or z < bmin.Y or z > bmax.Y then
			return
		end
		Waypoint.set(Vector3.new(x, 0, z), "Marked spot")
	end)
end

Waypoint.changed.Event:Connect(function(position)
	if worldMarker then
		worldMarker.Visible = position ~= nil
		if position then
			worldMarker.Position = toWorld(position.X, position.Z)
		end
	end
end)

local function refreshStamps()
	local found = DiscoveryList.found(player)
	for id, stamp in stamps do
		stamp.Visible = found[id] == true
	end
end
player:GetAttributeChangedSignal("Discovered"):Connect(refreshStamps)

local function refreshRich()
	if not worldRich then
		return
	end
	local rich = ReplicatedStorage:GetAttribute("RichField")
	worldRich.Visible = typeof(rich) == "Vector3"
	if typeof(rich) == "Vector3" then
		worldRich.Position = toWorld(rich.X, rich.Z)
	end
end
ReplicatedStorage:GetAttributeChangedSignal("RichField"):Connect(refreshRich)

-- Weather per region (Weather.luau publishes "Weather_<region id>") and the running region event ("RegionEvent",
-- "RegionEventAt"). Both are just ReplicatedStorage attributes, so they work with streaming.
local WEATHER_ICONS = {
	rain = "🌧 Rain",
	snow = "❄ Snow",
	dust = "💨 Dust",
	fog = "🌫 Fog",
	ash = "🌋 Ash",
	mist = "🌫 Mist",
}
local function refreshWeather()
	for id, label in weatherLabels do
		local kind = ReplicatedStorage:GetAttribute("Weather_" .. id)
		label.Text = kind and WEATHER_ICONS[kind] or ""
	end
end
local function refreshEvent()
	if not worldEvent then
		return
	end
	local name = ReplicatedStorage:GetAttribute("RegionEvent")
	local at = ReplicatedStorage:GetAttribute("RegionEventAt")
	worldEvent.Visible = typeof(name) == "string" and name ~= "" and typeof(at) == "Vector3"
	if worldEvent.Visible then
		worldEvent.Text = "! " .. string.upper(name)
		worldEvent.Position = toWorld(at.X, at.Z)
	end
end
ReplicatedStorage.AttributeChanged:Connect(function(name)
	if string.sub(name, 1, 8) == "Weather_" then
		refreshWeather()
	elseif name == "RegionEvent" or name == "RegionEventAt" then
		refreshEvent()
		local event = ReplicatedStorage:GetAttribute("RegionEvent")
		if name == "RegionEvent" and typeof(event) == "string" and event ~= "" then
			-- A short HUD toast (Main.client.luau shows ToastText when ToastId changes).
			player:SetAttribute("ToastText", ("%s has started! Press M to see where."):format(event))
			player:SetAttribute("ToastId", -math.floor(os.clock() * 1000))
		end
	end
end)

-- Side column: regions, places, clear.
local side = Instance.new("Frame")
side.Position = UDim2.fromOffset(CANVAS + 12, 0)
side.Size = UDim2.new(1, -(CANVAS + 12), 1, 0)
side.BackgroundTransparency = 1
side.Parent = mapBody
local sideList = Kit.list(side, 6)

local function heading(text, order)
	local h = Kit.label(sideList, text, { size = T.Heading, font = F.Title })
	h.LayoutOrder = order
	return h
end

-- MEADOW / WORLD switch (the world view needs Config/WorldMap).
local mapTitle = mapPanel:FindFirstChild("TitleBar") and mapPanel.TitleBar:FindFirstChildOfClass("TextLabel")
local worldView = false
local viewRow = Instance.new("Frame")
viewRow.Size = UDim2.new(1, 0, 0, 30)
viewRow.BackgroundTransparency = 1
viewRow.LayoutOrder = 0
viewRow.Visible = worldCanvas ~= nil
viewRow.Parent = sideList
local _, selectView = Kit.tabs(viewRow, { "MEADOW", "WORLD" }, function(index)
	worldView = index == 2 and worldCanvas ~= nil
	canvas.Visible = not worldView
	if worldCanvas then
		worldCanvas.Visible = worldView
	end
	if mapTitle then
		mapTitle.Text = worldView and "MAP  ·  THE STITCHED ISLES" or "MAP  ·  MEADOW FARM"
	end
	refreshRich()
	refreshWeather()
	refreshEvent()
	refreshStamps()
end)

-- Regions: every one on Config/WorldMap, with the one you're in marked.
local regionLabels = {}
local regionList = {}
table.insert(regionList, { name = "Meadow Farm", blurb = "Starter fields, the dealer, the bank and land for sale." })
if WorldMap then
	for _, r in WorldMap.Regions do
		table.insert(regionList, { name = r.name, center = r.center })
	end
	if WorldMap.SkyIsland then
		table.insert(regionList, { name = "Sky Island", blurb = "By zeppelin from Homestead Valley." })
	end
else
	table.insert(regionList, { name = "Homestead Valley", blurb = "North road. Coming soon." })
	table.insert(regionList, { name = "Pine Forest", blurb = "South road. Coming soon." })
end

heading("REGIONS", 1)
for i, region in regionList do
	local card = Kit.card(sideList, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.LayoutOrder = 1 + i
	Kit.pad(card, 6)
	local cardLayout = Instance.new("UIListLayout")
	cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
	cardLayout.Parent = card
	local title = Kit.label(card, region.name, { size = T.Small + 1, font = F.Bold })
	title.LayoutOrder = 1
	regionLabels[region.name] = { label = title, card = card }
	if region.blurb then
		local b = Kit.label(card, region.blurb, { size = T.Small, color = C.InkSoft, auto = true })
		b.LayoutOrder = 2
	end
	if region.center then
		-- Click a far region to mark its middle.
		local hit = Instance.new("TextButton")
		hit.Size = UDim2.fromScale(1, 1)
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.ZIndex = 3
		hit.Parent = card
		hit.Activated:Connect(function()
			Waypoint.set(Vector3.new(region.center.X, 0, region.center.Y), region.name)
		end)
	end
end

local shownRegion = nil
local function markRegion(name)
	if name == shownRegion then
		return
	end
	shownRegion = name
	for regionName, r in regionLabels do
		local here = regionName == name
		r.label.Text = regionName .. (here and "  ·  you are here" or "")
		r.card.BackgroundColor3 = here and C.Picked or C.Card
	end
end

heading("GO TO", 50)
for i, place in Places.List do
	local b = Kit.button(sideList, place.name, "plain", UDim2.new(1, 0, 0, 28))
	b.LayoutOrder = 50 + i
	b.TextSize = T.Small
	b.Activated:Connect(function()
		Waypoint.set(Places.get(place.id), place.name)
		Menus.close()
	end)
end
local plotButton = Kit.button(sideList, "Your plot", "go", UDim2.new(1, 0, 0, 28))
plotButton.LayoutOrder = 70
plotButton.TextSize = T.Small
plotButton.Activated:Connect(function()
	local p = Places.myPlot()
	if p then
		Waypoint.set(p, "Your plot")
		Menus.close()
	end
end)
local clearButton = Kit.button(sideList, "Clear marker", "stop", UDim2.new(1, 0, 0, 28))
clearButton.LayoutOrder = 71
clearButton.TextSize = T.Small
clearButton.Activated:Connect(Waypoint.clear)
local hint = Kit.label(sideList, "Click a spot or a place on the map to mark it. Follow the glowing line.", {
	size = T.Small,
	color = C.InkSoft,
	auto = true,
})
hint.LayoutOrder = 72

local mapLoop = nil
Menus.register("Map", function(open)
	mapPanel.Visible = open
	if mapLoop then
		mapLoop:Disconnect()
		mapLoop = nil
	end
	if not open then
		return
	end
	plotButton.Visible = Places.myPlot() ~= nil
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local outside = root and regionAt(root.Position) ~= "Meadow Farm"
	selectView(outside and worldCanvas and 2 or 1)
	if root then
		markRegion(regionAt(root.Position))
	end
	refreshPlots()
	placeLandmarks()
	refreshTrucks()
	local lastTrucks = os.clock()
	mapLoop = RunService.RenderStepped:Connect(function()
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		me.Visible = root ~= nil
		if root then
			local look = Workspace.CurrentCamera.CFrame.LookVector
			local yaw = math.deg(math.atan2(look.X, -look.Z))
			me.Position = toMap(root.Position.X, root.Position.Z)
			me.Rotation = yaw
			if worldMe then
				worldMe.Position = toWorld(root.Position.X, root.Position.Z)
				worldMe.Rotation = yaw
			end
		end
		if os.clock() - lastTrucks > 1 then
			lastTrucks = os.clock()
			refreshTrucks()
			if root then
				markRegion(regionAt(root.Position))
			end
		end
	end)
end)

-- Shop -------------------------------------------------------------------------------------------------------------

local SHOP_W, SHOP_H = 560, 520
local shopPanel, shopBody = Kit.panel(gui, {
	name = "Shop",
	title = "SHOP",
	width = SHOP_W,
	height = SHOP_H,
	onClose = function()
		Menus.close()
	end,
})

local shopCash = Kit.label(shopBody, "", { size = T.Heading, font = F.Bold, color = C.Green, height = 22 })
local shopNote =
	Kit.label(shopBody, "Prices for everything. Press SHOW ME and follow the line to the counter that sells it.", {
		size = T.Small,
		color = C.InkSoft,
		height = 18,
	})
shopNote.Position = UDim2.fromOffset(0, 22)
local tabHolder = Instance.new("Frame")
tabHolder.Position = UDim2.fromOffset(0, 46)
tabHolder.Size = UDim2.new(1, 0, 0, 32)
tabHolder.BackgroundTransparency = 1
tabHolder.Parent = shopBody
local listHolder = Instance.new("Frame")
listHolder.Position = UDim2.fromOffset(0, 86)
listHolder.Size = UDim2.new(1, 0, 1, -112)
listHolder.BackgroundTransparency = 1
listHolder.Parent = shopBody
local shopList = Kit.list(listHolder, 8)
local shopMessage = Kit.label(shopBody, "", { size = T.Small, font = F.Medium, color = C.Green, height = 20 })
shopMessage.Position = UDim2.new(0, 0, 1, -20)

local currentTab = 1

local STATE_TEXT = {
	owned = { "OWNED", "muted" },
	wearing = { "WEARING", "muted" },
	soon = { "SOON", "muted" },
	taken = { "TAKEN", "muted" },
	needland = { "BUY LAND FIRST", "wood" },
	buy = { "SHOW ME", "go" },
}

local function renderShop()
	for _, child in shopList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local cash = player:GetAttribute("Cash") or 0
	shopCash.Text = "Your cash: " .. Kit.money(cash)
	local tab = Catalog.Tabs[currentTab]
	for i, row in Catalog.items(tab) do
		local card = Kit.card(shopList, 74)
		card.LayoutOrder = i
		local name = Kit.label(card, row.name, { size = T.Heading, font = F.Bold, wrap = false })
		name.Position = UDim2.fromOffset(10, 6)
		name.Size = UDim2.new(1, -170, 0, 20)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local blurb = Kit.label(card, row.blurb or "", { size = T.Small, color = C.InkSoft })
		blurb.Position = UDim2.fromOffset(10, 28)
		blurb.Size = UDim2.new(1, -170, 0, 40)
		blurb.TextYAlignment = Enum.TextYAlignment.Top

		local priceText
		local priceColor = C.Ink
		if row.robux then
			priceText = ("R$ %d"):format(row.robux)
		elseif tab == "Robux" then
			priceText = "R$ soon"
		elseif row.price then
			priceText = Kit.money(row.price)
			if row.state == "buy" and not GameConfig.InfiniteMoney and cash < row.price then
				priceText ..= ("  (need %s)"):format(Kit.money(row.price - cash))
				priceColor = C.Red
			end
		end
		local price = Kit.label(
			card,
			priceText or "",
			{ size = T.Body, font = F.Bold, color = priceColor, align = "right", wrap = false }
		)
		price.AnchorPoint = Vector2.new(1, 0)
		price.Position = UDim2.new(1, -10, 0, 6)
		price.Size = UDim2.fromOffset(150, 20)

		local look = STATE_TEXT[row.state] or STATE_TEXT.soon
		local text = look[1]
		if tab == "Gloves" and row.state == "owned" then
			text, look = "WEAR IT", { "WEAR IT", "wood" }
		end
		local button = Kit.button(card, text, look[2], UDim2.fromOffset(140, 30))
		button.AnchorPoint = Vector2.new(1, 1)
		button.Position = UDim2.new(1, -10, 1, -8)
		button.TextSize = T.Small
		local clickable = row.place ~= nil
			and (row.state == "buy" or row.state == "needland" or (tab == "Gloves" and row.state == "owned"))
		button.AutoButtonColor = clickable
		button.Activated:Connect(function()
			if not clickable then
				return
			end
			local where = Places.get(row.place)
			if where then
				Waypoint.set(where, Places.name(row.place))
				shopMessage.Text = ("Marked %s. Follow the line."):format(Places.name(row.place))
				task.delay(0.6, function()
					if Menus.current() == "Shop" then
						Menus.close()
					end
				end)
			end
		end)
	end
end

local _, selectTab = Kit.tabs(tabHolder, Catalog.Tabs, function(index)
	currentTab = index
	shopMessage.Text = ""
	renderShop()
end)

local shopOpen = false
Menus.register("Shop", function(open)
	shopPanel.Visible = open
	shopOpen = open
	if open then
		shopMessage.Text = ""
		selectTab(currentTab)
	end
end)
for _, name in { "Cash", "OwnedTrucks", "OwnedTrailers", "GlovesOwned", "GloveId", "LandPlot" } do
	player:GetAttributeChangedSignal(name):Connect(function()
		if shopOpen then
			renderShop()
		end
	end)
end

-- Let other scripts open a shop tab: Menus.event("ShopTab"):Fire("Trucks")
Menus.event("ShopTab").Event:Connect(function(tabName)
	local index = table.find(Catalog.Tabs, tabName)
	if index then
		currentTab = index
	end
	if Menus.current() == "Shop" then
		selectTab(currentTab)
	else
		Menus.open("Shop")
	end
end)
