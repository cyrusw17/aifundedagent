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
text(panel, "Pick a save to play.", 15, 42, 20, INK, Enum.Font.Gotham)
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

local function show(slots, online)
	for i, slot in slots do
		local card = Instance.new("Frame")
		card.Position = UDim2.fromOffset(14, 72 + (i - 1) * 96)
		card.Size = UDim2.new(1, -28, 0, 86)
		card.BackgroundColor3 = CARD
		card.Parent = panel
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)
		text(card, (slot.used and "LOAD %d" or "SAVE %d"):format(i), 18, 8, 22)
		local info = text(card, describe(slot), 13, 30, 34, INK, Enum.Font.Gotham)
		info.Size = UDim2.new(1, -150, 0, 48)
		local button = Instance.new("TextButton")
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -10, 0.5, 0)
		button.Size = UDim2.fromOffset(110, 40)
		button.Font = Enum.Font.GothamBold
		button.TextSize = 16
		button.Text = slot.used and "LOAD" or "NEW GAME"
		button.TextColor3 = Color3.new(1, 1, 1)
		button.BackgroundColor3 = slot.used and GREEN or BROWN
		button.Parent = card
		Instance.new("UICorner", button).CornerRadius = UDim.new(0, 6)
		button.Activated:Connect(function()
			if busy then
				return
			end
			busy = true
			message.TextColor3 = INK
			message.Text = slot.used and "Loading..." or "Starting..."
			local ok, chosen, reply = pcall(function()
				return chooseRemote:InvokeServer(i)
			end)
			busy = false
			if ok and chosen then
				gui:Destroy()
			else
				message.TextColor3 = RED
				message.Text = ok and (reply or "Couldn't load that save.") or "Couldn't reach the server. Try again."
			end
		end)
	end
	if online then
		message.Text = ""
	else
		message.TextColor3 = RED
		message.Text = "Saving is off, so this game won't be kept. In Studio, turn on Game Settings > Security > "
			.. "Enable Studio Access to API Services."
	end
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
