--!nonstrict
-- The save picker shown on joining: three slots, Save 1-3 for empty ones and Load 1-3 for used ones. Nothing in the
-- game is loaded for you until you pick one (Data.luau).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LandConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Land"))
local remotes = ReplicatedStorage:WaitForChild("SaveSlots")
local listRemote = remotes:WaitForChild("List")
local chooseRemote = remotes:WaitForChild("Choose")

local player = Players.LocalPlayer

local INK = Color3.fromRGB(40, 34, 28)
local PANEL = Color3.fromRGB(199, 186, 153)
local CARD = Color3.fromRGB(222, 212, 184)
local RED = Color3.fromRGB(133, 61, 48)
local GREEN = Color3.fromRGB(87, 107, 71)
local BROWN = Color3.fromRGB(110, 88, 64)

if player:GetAttribute("SaveSlot") then
	return -- already picked (the script reran)
end

local gui = Instance.new("ScreenGui")
gui.Name = "SaveSlotsGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 50
gui.Parent = player:WaitForChild("PlayerGui")

local shade = Instance.new("Frame")
shade.Size = UDim2.fromScale(1, 1)
shade.BackgroundColor3 = Color3.new(0, 0, 0)
shade.BackgroundTransparency = 0.35
shade.Active = true
shade.Parent = gui

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(420, 430)
panel.BackgroundColor3 = PANEL
panel.Parent = shade
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)
local stroke = Instance.new("UIStroke", panel)
stroke.Color = INK
stroke.Thickness = 2
local constraint = Instance.new("UISizeConstraint", panel)
constraint.MaxSize = Vector2.new(420, 430)
local scale = Instance.new("UIScale", panel)
local function fit()
	local view = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(800, 600)
	scale.Scale = math.min(1, (view.X - 24) / 420, (view.Y - 24) / 430)
end
fit()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)

local function text(parent, value, size, y, height, color, font)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(14, y)
	label.Size = UDim2.new(1, -28, 0, height)
	label.Font = font or Enum.Font.GothamBold
	label.TextSize = size
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = color or INK
	label.Text = value
	label.Parent = parent
	return label
end

text(panel, "NEEDLEWOOD", 26, 12, 30)
local message = text(panel, "Loading your saves...", 13, 366, 52, RED, Enum.Font.Gotham)

local busy = false

local function describe(slot)
	if not slot.used then
		return slot.preset and "Empty. Starts as your preset farm: truck, trailer, silo and a working line." or "Empty. Starts a new farm."
	end
	local plot = slot.plot and LandConfig.Plots[slot.plot]
	local parts = { ("$%d"):format(slot.cash or 0) }
	table.insert(parts, plot and plot.name or "no land yet")
	if (slot.trucks or 0) > 0 then
		table.insert(parts, slot.trucks == 1 and "1 truck" or ("%d trucks"):format(slot.trucks))
	end
	if slot.savedAt then
		table.insert(parts, "saved " .. os.date("%b %d, %H:%M", slot.savedAt))
	end
	return table.concat(parts, "  ·  ")
end

local content = Instance.new("Frame")
content.BackgroundTransparency = 1
content.Size = UDim2.fromScale(1, 1)
content.Parent = panel
local title = text(panel, "", 15, 42, 20, INK, Enum.Font.Gotham)
local savedSlots, savedOnline = nil, false

local function clear()
	for _, child in content:GetChildren() do
		child:Destroy()
	end
end

local function makeButton(parent, label, color)
	local b = Instance.new("TextButton")
	b.Font = Enum.Font.GothamBold
	b.TextSize = 14
	b.TextWrapped = true
	b.Text = label
	b.TextColor3 = Color3.new(1, 1, 1)
	b.BackgroundColor3 = color
	b.Parent = parent
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
	return b
end

local function start(i, slot, plot)
	if busy then
		return
	end
	busy = true
	message.TextColor3 = INK
	message.Text = slot.used and "Loading..." or "Starting..."
	local ok, chosen, reply = pcall(function()
		return chooseRemote:InvokeServer(i, plot)
	end)
	busy = false
	if ok and chosen then
		gui:Destroy()
	else
		message.TextColor3 = RED
		message.Text = ok and (reply or "Couldn't load that save.") or "Couldn't reach the server. Try again."
	end
end

local showSlots

-- Step 2: where the farm goes. A save with land (or a preset) picks any free plot to farm on; a save with no land
-- can buy a plot right away or start without one.
local function showPlots(i, slot)
	clear()
	local hasLand = slot.plot ~= nil
	title.Text = hasLand and ("Save %d: pick the plot for your farm."):format(i)
		or ("Save %d: buy a plot now, or start without land."):format(i)
	local state = ReplicatedStorage:WaitForChild("Land", 10)
	local infos = {}
	if state then
		for _, info in state:GetChildren() do
			if info:IsA("Configuration") then
				infos[info:GetAttribute("Index")] = info
			end
		end
	end

	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(14, 68)
	list.Size = UDim2.new(1, -28, 0, 248)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = content
	local layout = Instance.new("UIListLayout", list)
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder

	for index, def in LandConfig.Plots do
		local info = infos[index]
		local ownerId = info and info:GetAttribute("OwnerId") or 0
		local card = Instance.new("Frame")
		card.LayoutOrder = index
		card.Size = UDim2.new(1, -8, 0, 52)
		card.BackgroundColor3 = CARD
		card.Parent = list
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)
		local name = def.name .. (hasLand and slot.plot == index and "  (your farm)" or "")
		text(card, name, 15, 4, 20)
		local size = ("%d x %d tiles"):format(def.tiles.X, def.tiles.Y)
		text(card, hasLand and size or ("%s  ·  $%d"):format(size, def.price), 12, 26, 18, INK, Enum.Font.Gotham)
		local b
		if ownerId ~= 0 and ownerId ~= player.UserId then
			b = makeButton(card, "TAKEN", Color3.fromRGB(150, 140, 120))
			b.AutoButtonColor = false
		else
			b = makeButton(card, hasLand and "FARM HERE" or "BUY", GREEN)
			b.Activated:Connect(function()
				start(i, slot, index)
			end)
		end
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.new(1, -8, 0.5, 0)
		b.Size = UDim2.fromOffset(100, 34)
	end

	local back = makeButton(content, "BACK", Color3.fromRGB(150, 140, 120))
	back.Position = UDim2.fromOffset(14, 322)
	back.Size = UDim2.fromOffset(90, 34)
	back.Activated:Connect(function()
		message.Text = ""
		showSlots()
	end)
	if not hasLand then
		local skip = makeButton(content, "START WITHOUT LAND", BROWN)
		skip.Position = UDim2.new(1, -194, 0, 322)
		skip.Size = UDim2.fromOffset(180, 34)
		skip.Activated:Connect(function()
			start(i, slot, nil)
		end)
	end
end

-- Step 1: the three slots.
function showSlots()
	clear()
	title.Text = "Pick a save to play."
	for i, slot in savedSlots do
		local card = Instance.new("Frame")
		card.Position = UDim2.fromOffset(14, 72 + (i - 1) * 96)
		card.Size = UDim2.new(1, -28, 0, 86)
		card.BackgroundColor3 = CARD
		card.Parent = content
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)
		text(card, (slot.used and "LOAD %d" or "SAVE %d"):format(i), 18, 8, 22)
		local info = text(card, describe(slot), 13, 30, 34, INK, Enum.Font.Gotham)
		info.Size = UDim2.new(1, -150, 0, 48)
		local button = makeButton(card, slot.used and "LOAD" or "NEW GAME", slot.used and GREEN or BROWN)
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -10, 0.5, 0)
		button.Size = UDim2.fromOffset(110, 40)
		button.TextSize = 16
		button.Activated:Connect(function()
			if not busy then
				showPlots(i, slot)
			end
		end)
	end
	if savedOnline then
		message.Text = ""
	else
		message.TextColor3 = RED
		message.Text = "Saving is off, so this game won't be kept. In Studio, turn on Game Settings > Security > "
			.. "Enable Studio Access to API Services."
	end
end

local function show(slots, online)
	savedSlots, savedOnline = slots, online
	showSlots()
end

local ok, slots, online = pcall(function()
	return listRemote:InvokeServer()
end)
if ok and typeof(slots) == "table" then
	show(slots, online)
else
	message.Text = "Couldn't read your saves. Starting a new game."
	show({ { used = false }, { used = false }, { used = false } }, false)
end
