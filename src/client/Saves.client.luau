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

local Kit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UI"):WaitForChild("Kit"))
local Theme = Kit.Theme
local C, F, T = Theme.Colors, Theme.Fonts, Theme.Text

if player:GetAttribute("SaveSlot") then
	return -- already picked (the script reran)
end

local gui = Kit.screen("SaveSlotsGui", 50, true)

local shade = Instance.new("Frame")
shade.Size = UDim2.fromScale(1, 1)
shade.BackgroundColor3 = C.Shade
shade.BackgroundTransparency = 0.35
shade.Active = true
shade.Parent = gui

local W, H = 440, 590
local _, body = Kit.panel(shade, { title = "NEEDLEWOOD", width = W, height = H })

local subtitle = Kit.label(body, "Pick a save to play.", { size = T.Body, font = F.Medium, color = C.InkSoft, height = 20 })

-- Returning players get one big button for the save they played last.
local continueButton = Kit.button(body, "CONTINUE", "go", UDim2.new(1, 0, 0, 56))
continueButton.Position = UDim2.fromOffset(0, 26)
continueButton.Font = F.Title
continueButton.TextSize = 22
continueButton.Visible = false

local slotsFrame = Instance.new("Frame")
slotsFrame.BackgroundTransparency = 1
slotsFrame.Position = UDim2.fromOffset(0, 26)
slotsFrame.Size = UDim2.new(1, 0, 0, 300)
slotsFrame.Parent = body
local slotLayout = Instance.new("UIListLayout")
slotLayout.Padding = UDim.new(0, 8)
slotLayout.SortOrder = Enum.SortOrder.LayoutOrder
slotLayout.Parent = slotsFrame

local message = Kit.label(body, "Loading your saves...", { size = T.Small, color = C.Red, height = 48 })
message.AnchorPoint = Vector2.new(0, 1)
message.Position = UDim2.new(0, 0, 1, 0)
message.TextYAlignment = Enum.TextYAlignment.Top

local busy = false

local function describe(slot)
	if not slot.used then
		return slot.preset and "Empty. Starts as your preset farm: truck, trailer, silo and a working line." or "Empty. Starts a new farm."
	end
	local plot = slot.plot and LandConfig.Plots[slot.plot]
	local parts = { Kit.money(slot.cash or 0) }
	table.insert(parts, plot and plot.name or "no land yet")
	if (slot.trucks or 0) > 0 then
		table.insert(parts, slot.trucks == 1 and "1 truck" or ("%d trucks"):format(slot.trucks))
	end
	if slot.savedAt then
		table.insert(parts, "saved " .. os.date("%b %d, %H:%M", slot.savedAt))
	end
	return table.concat(parts, "  ·  ")
end

local function pick(i, used)
	if busy then
		return
	end
	busy = true
	message.TextColor3 = C.Ink
	message.Text = used and "Loading..." or "Starting..."
	local ok, chosen, reply = pcall(function()
		return chooseRemote:InvokeServer(i)
	end)
	busy = false
	if ok and chosen then
		gui:Destroy()
	else
		message.TextColor3 = C.Red
		message.Text = ok and (reply or "Couldn't load that save.") or "Couldn't reach the server. Try again."
	end
end

local function show(slots, online)
	-- The last save played, for CONTINUE.
	local latest, latestAt = nil, -1
	for i, slot in slots do
		if slot.used and (slot.savedAt or 0) > latestAt then
			latest, latestAt = i, slot.savedAt or 0
		end
	end
	if latest then
		continueButton.Visible = true
		continueButton.Text = ("CONTINUE  ·  SAVE %d"):format(latest)
		continueButton.Activated:Connect(function()
			pick(latest, true)
		end)
		slotsFrame.Position = UDim2.fromOffset(0, 92)
		subtitle.Text = "Welcome back. Pick up where you left off, or choose a save."
	end

	for i, slot in slots do
		local card = Kit.card(slotsFrame, 88)
		card.LayoutOrder = i
		local title = Kit.label(card, (slot.used and "SAVE %d" or "EMPTY SLOT %d"):format(i), { size = T.Heading, font = F.Title, wrap = false })
		title.Position = UDim2.fromOffset(12, 8)
		title.Size = UDim2.new(1, -150, 0, 22)
		local info = Kit.label(card, describe(slot), { size = T.Small, color = C.InkSoft })
		info.Position = UDim2.fromOffset(12, 32)
		info.Size = UDim2.new(1, -150, 0, 48)
		info.TextYAlignment = Enum.TextYAlignment.Top
		local button = Kit.button(card, slot.used and "LOAD" or "NEW GAME", slot.used and "go" or "wood", UDim2.fromOffset(116, 40))
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -12, 0.5, 0)
		button.Activated:Connect(function()
			pick(i, slot.used)
		end)
	end
	if online then
		message.Text = ""
	else
		message.TextColor3 = C.Red
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
