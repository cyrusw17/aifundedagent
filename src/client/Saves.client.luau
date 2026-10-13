--!nonstrict
-- The save picker shown on joining. Step 1 picks one of three slots (or CONTINUE for the last one played), step 2
-- picks a free plot for the farm. Nothing in the game is loaded for you until you pick (Data.luau).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LandConfig = require(Shared:WaitForChild("Config"):WaitForChild("Land"))
local Kit = require(Shared:WaitForChild("UI"):WaitForChild("Kit"))
local remotes = ReplicatedStorage:WaitForChild("SaveSlots")
local listRemote = remotes:WaitForChild("List")
local chooseRemote = remotes:WaitForChild("Choose")

local player = Players.LocalPlayer
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

local _, body = Kit.panel(shade, { title = "NEEDLEWOOD", width = 440, height = 590 })

local title = Kit.label(body, "", { size = T.Body, font = F.Medium, color = C.InkSoft, height = 20 })
local content = Instance.new("Frame")
content.BackgroundTransparency = 1
content.Position = UDim2.fromOffset(0, 26)
content.Size = UDim2.new(1, 0, 1, -80)
content.Parent = body
local message = Kit.label(body, "Loading your saves...", { size = T.Small, color = C.Red, height = 48 })
message.AnchorPoint = Vector2.new(0, 1)
message.Position = UDim2.new(0, 0, 1, 0)
message.TextYAlignment = Enum.TextYAlignment.Top

local busy = false
local savedSlots, savedOnline = nil, false

local function describe(slot)
	if not slot.used then
		return slot.preset and "Empty. Starts as your preset farm: truck, trailer, silo and a working line."
			or "Empty. Starts a new farm."
	end
	local parts = { Kit.money(slot.cash or 0) }
	table.insert(parts, slot.plot and "owns a farm" or "no land yet")
	if (slot.trucks or 0) > 0 then
		table.insert(parts, slot.trucks == 1 and "1 truck" or ("%d trucks"):format(slot.trucks))
	end
	if slot.savedAt then
		table.insert(parts, "saved " .. os.date("%b %d, %H:%M", slot.savedAt))
	end
	return table.concat(parts, "  ·  ")
end

local function clear()
	for _, child in content:GetChildren() do
		child:Destroy()
	end
end

local function plotInfos()
	local state = ReplicatedStorage:WaitForChild("Land", 10)
	local infos = {}
	for _, info in state and state:GetChildren() or {} do
		if info:IsA("Configuration") then
			infos[info:GetAttribute("Index")] = info
		end
	end
	return infos
end

local function isFree(infos, index)
	local info = infos[index]
	local ownerId = info and info:GetAttribute("OwnerId") or 0
	return ownerId == 0 or ownerId == player.UserId
end

local function start(i, slot, plot)
	if busy then
		return
	end
	busy = true
	message.TextColor3 = C.Ink
	message.Text = slot.used and "Loading..." or "Starting..."
	local ok, chosen, reply = pcall(function()
		return chooseRemote:InvokeServer(i, plot)
	end)
	busy = false
	if ok and chosen then
		gui:Destroy()
	else
		message.TextColor3 = C.Red
		message.Text = ok and (reply or "Couldn't load that save.") or "Couldn't reach the server. Try again."
	end
end

local showSlots

-- Step 2: where the farm goes. Every plot is the same, and only plots nobody on this server has taken can be picked.
-- A save with land (or a preset) rebuilds its farm on the plot picked; a save with no land can buy one right away or
-- start without one.
local function showPlots(i, slot)
	clear()
	local hasLand = slot.plot ~= nil
	title.Text = hasLand and ("Save %d: pick a free plot. Your farm is rebuilt there."):format(i)
		or ("Save %d: buy a free plot now, or start without land."):format(i)
	local infos = plotInfos()

	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 1, -44)
	holder.Parent = content
	local list = Kit.list(holder, 6)

	for index, def in LandConfig.Plots do
		local taken = not isFree(infos, index)
		local card = Kit.card(list, 56)
		card.LayoutOrder = index
		local name = Kit.label(card, def.name, { size = T.Heading, font = F.Bold, wrap = false })
		name.Position = UDim2.fromOffset(12, 4)
		name.Size = UDim2.new(1, -130, 0, 22)
		local where = def.open == "S" and "south of the lane" or "north of the lane"
		local detail = taken and ("%s  ·  taken"):format(where)
			or hasLand and ("%s  ·  free"):format(where)
			or ("%s  ·  %s"):format(where, Kit.money(def.price))
		local info = Kit.label(card, detail, { size = T.Small, color = C.InkSoft })
		info.Position = UDim2.fromOffset(12, 28)
		info.Size = UDim2.new(1, -130, 0, 18)
		local b
		if taken then
			b = Kit.button(card, "TAKEN", "muted", UDim2.fromOffset(100, 34))
			b.AutoButtonColor = false
		else
			b = Kit.button(card, hasLand and "FARM HERE" or "BUY", "go", UDim2.fromOffset(100, 34))
			b.Activated:Connect(function()
				start(i, slot, index)
			end)
		end
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.new(1, -10, 0.5, 0)
	end

	local back = Kit.button(content, "BACK", "plain", UDim2.fromOffset(90, 34))
	back.AnchorPoint = Vector2.new(0, 1)
	back.Position = UDim2.new(0, 0, 1, 0)
	back.Activated:Connect(function()
		message.Text = ""
		showSlots()
	end)
	if not hasLand then
		local skip = Kit.button(content, "START WITHOUT LAND", "wood", UDim2.fromOffset(190, 34))
		skip.AnchorPoint = Vector2.new(1, 1)
		skip.Position = UDim2.new(1, 0, 1, 0)
		skip.Activated:Connect(function()
			start(i, slot, nil)
		end)
	end
end

-- CONTINUE: the last save played, straight onto its old plot when that is still free, else to the plot picker.
local function continueSlot(i, slot)
	if busy then
		return
	end
	if not slot.plot then
		start(i, slot, nil)
	elseif typeof(slot.plot) == "number" and LandConfig.Plots[slot.plot] and isFree(plotInfos(), slot.plot) then
		start(i, slot, slot.plot)
	else
		showPlots(i, slot)
	end
end

-- Step 1: the three slots.
function showSlots()
	clear()
	local latest, latestAt = nil, -1
	for i, slot in savedSlots do
		if slot.used and (slot.savedAt or 0) > latestAt then
			latest, latestAt = i, slot.savedAt or 0
		end
	end

	local y = 0
	if latest then
		title.Text = "Welcome back. Pick up where you left off, or choose a save."
		local continueButton =
			Kit.button(content, ("CONTINUE  ·  SAVE %d"):format(latest), "go", UDim2.new(1, 0, 0, 56))
		continueButton.Font = F.Title
		continueButton.TextSize = 22
		continueButton.Activated:Connect(function()
			continueSlot(latest, savedSlots[latest])
		end)
		y = 66
	else
		title.Text = "Pick a save to play."
	end

	for i, slot in savedSlots do
		local card = Kit.card(content, 88)
		card.Position = UDim2.fromOffset(0, y + (i - 1) * 96)
		local name = Kit.label(
			card,
			(slot.used and "SAVE %d" or "EMPTY SLOT %d"):format(i),
			{ size = T.Heading, font = F.Title, wrap = false }
		)
		name.Position = UDim2.fromOffset(12, 8)
		name.Size = UDim2.new(1, -150, 0, 22)
		local info = Kit.label(card, describe(slot), { size = T.Small, color = C.InkSoft })
		info.Position = UDim2.fromOffset(12, 32)
		info.Size = UDim2.new(1, -150, 0, 48)
		info.TextYAlignment = Enum.TextYAlignment.Top
		local button = Kit.button(
			card,
			slot.used and "LOAD" or "NEW GAME",
			slot.used and "go" or "wood",
			UDim2.fromOffset(116, 40)
		)
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -12, 0.5, 0)
		button.Activated:Connect(function()
			if not busy then
				showPlots(i, slot)
			end
		end)
	end
	if savedOnline then
		message.Text = ""
	else
		message.TextColor3 = C.Red
		message.Text = "Your saves couldn't be loaded, so this game won't be saved. Rejoin to try again. In Studio, "
			.. "turn on Game Settings > Security > Enable Studio Access to API Services."
	end
end

local ok, slots, online = pcall(function()
	return listRemote:InvokeServer()
end)
if ok and typeof(slots) == "table" then
	savedSlots, savedOnline = slots, online
else
	message.Text = "Couldn't read your saves. Starting a new game."
	savedSlots, savedOnline = { { used = false }, { used = false }, { used = false } }, false
end
showSlots()
