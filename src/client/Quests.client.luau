--!nonstrict
-- The quest log (Q, or click the tracker under the HUD), the tracker with the clock, and the quest markers in the
-- world. The server decides every step (src/server/Services/Quests.luau); this script only shows it.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")

local remotes = ReplicatedStorage:WaitForChild("Quests")
local getRemote = remotes:WaitForChild("Get")
local actionRemote = remotes:WaitForChild("Action")
local changedRemote = remotes:WaitForChild("Changed")

local player = Players.LocalPlayer

-- Rustic palette, matching the land office panel.
local INK = Color3.fromRGB(40, 34, 28)
local SOFT = Color3.fromRGB(96, 84, 68)
local PANEL = Color3.fromRGB(199, 186, 153)
local CARD = Color3.fromRGB(222, 212, 184)
local GREEN = Color3.fromRGB(87, 107, 71)
local RED = Color3.fromRGB(133, 61, 48)
local GOLD = Color3.fromRGB(176, 146, 82)
local MUTED = Color3.fromRGB(150, 140, 120)

local gui = Instance.new("ScreenGui")
gui.Name = "QuestGui"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local function corner(instance, radius)
	Instance.new("UICorner", instance).CornerRadius = UDim.new(0, radius or 8)
end

local function padding(instance, px)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.PaddingTop = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.Parent = instance
end

-- A label that grows to fit its text, for use inside a list.
local function line(parent, text, size, color, font, order)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Font = font or Enum.Font.Gotham
	label.TextSize = size
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = color or INK
	label.Text = text
	label.LayoutOrder = order or 0
	label.Parent = parent
	return label
end

local function list(parent, gap)
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, gap or 4)
	layout.Parent = parent
	return layout
end

local function button(parent, text, color)
	local b = Instance.new("TextButton")
	b.Font = Enum.Font.GothamBold
	b.TextSize = 14
	b.Text = text
	b.TextColor3 = Color3.new(1, 1, 1)
	b.BackgroundColor3 = color or GREEN
	b.AutoButtonColor = true
	b.Parent = parent
	corner(b, 6)
	return b
end

-- Tracker: the clock and the quest you are on, under the HUD. Click it to open the log. ---------------------------

local tracker = Instance.new("TextButton")
tracker.Name = "QuestTracker"
tracker.Text = ""
tracker.AutoButtonColor = false
tracker.Position = UDim2.fromOffset(14, 134)
tracker.Size = UDim2.fromOffset(260, 0)
tracker.AutomaticSize = Enum.AutomaticSize.Y
tracker.BackgroundColor3 = Color3.fromRGB(20, 34, 26)
tracker.BackgroundTransparency = 0.25
tracker.Parent = gui
corner(tracker, 12)
padding(tracker, 10)
list(tracker, 2)

local clockLabel = line(tracker, "", 14, Color3.fromRGB(214, 226, 218), Enum.Font.GothamBold, 1)
local trackName = line(tracker, "", 15, Color3.fromRGB(255, 214, 120), Enum.Font.GothamBold, 2)
local trackStep = line(tracker, "", 14, Color3.new(1, 1, 1), Enum.Font.Gotham, 3)
line(tracker, "Q: quest log", 12, Color3.fromRGB(170, 186, 176), Enum.Font.Gotham, 4)

local function refreshTracker()
	local name = player:GetAttribute("QuestTrackName")
	trackName.Text = name or "No quest right now"
	trackName.Visible = true
	trackStep.Text = player:GetAttribute("QuestTrackStep") or ""
	trackStep.Visible = name ~= nil
	tracker.Visible = player:GetAttribute("SaveSlot") ~= nil
end
player:GetAttributeChangedSignal("QuestTrackName"):Connect(refreshTracker)
player:GetAttributeChangedSignal("QuestTrackStep"):Connect(refreshTracker)
player:GetAttributeChangedSignal("SaveSlot"):Connect(refreshTracker)
refreshTracker()

local function clockText()
	local hour = Lighting.ClockTime
	local h = math.floor(hour)
	local m = math.floor((hour - h) * 60)
	local part
	if hour >= 23 or hour < 1 then
		part = "Midnight"
	elseif hour >= 19.5 or hour < 5.5 then
		part = "Night"
	elseif hour >= 17.5 then
		part = "Dusk"
	else
		part = "Day"
	end
	return ("%02d:%02d  ·  %s"):format(h, m, part)
end
Lighting:GetPropertyChangedSignal("ClockTime"):Connect(function()
	clockLabel.Text = clockText()
end)
clockLabel.Text = clockText()

-- The log panel ----------------------------------------------------------------------------------------------------

local panel = Instance.new("Frame")
panel.Name = "QuestLog"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.new(0, 560, 0.8, 0)
panel.BackgroundColor3 = PANEL
panel.Visible = false
panel.Parent = gui
corner(panel, 12)
local sizeLimit = Instance.new("UISizeConstraint")
sizeLimit.MaxSize = Vector2.new(math.huge, 620)
sizeLimit.Parent = panel

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(16, 10)
title.Size = UDim2.new(1, -70, 0, 30)
title.Font = Enum.Font.GothamBlack
title.TextSize = 24
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = INK
title.Text = "Quest log"
title.Parent = panel

local close = button(panel, "X", RED)
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, -12, 0, 10)
close.Size = UDim2.fromOffset(34, 30)

local tabRow = Instance.new("Frame")
tabRow.BackgroundTransparency = 1
tabRow.Position = UDim2.fromOffset(16, 46)
tabRow.Size = UDim2.new(1, -32, 0, 30)
tabRow.Parent = panel
local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 6)
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.Parent = tabRow

local scroll = Instance.new("ScrollingFrame")
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.Position = UDim2.fromOffset(16, 84)
scroll.Size = UDim2.new(1, -24, 1, -96)
scroll.CanvasSize = UDim2.new()
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.ScrollBarThickness = 6
scroll.ScrollBarImageColor3 = SOFT
scroll.Parent = panel
list(scroll, 8)

local TABS = { "Quests", "Rituals", "Bounties", "Mystery items", "Rewards" }
local tab = "Quests"
local tabButtons = {}
local data = nil
local render -- forward declaration

for i, name in TABS do
	local b = button(tabRow, name, MUTED)
	b.LayoutOrder = i
	b.Size = UDim2.fromOffset(98, 30)
	b.TextSize = 13
	tabButtons[name] = b
	b.Activated:Connect(function()
		tab = name
		render()
	end)
end

local function card(order, color)
	local f = Instance.new("Frame")
	f.BackgroundColor3 = color or CARD
	f.Size = UDim2.new(1, -8, 0, 0)
	f.AutomaticSize = Enum.AutomaticSize.Y
	f.LayoutOrder = order
	f.Parent = scroll
	corner(f, 8)
	padding(f, 10)
	list(f, 3)
	return f
end

local localToasts = 0
local function act(kind, id)
	local ok, message = actionRemote:InvokeServer(kind, id)
	if message then
		-- Shown in the HUD toast (Main.client.luau watches ToastId). Only this player sees it.
		-- Negative ids never collide with the server's own (positive) toast ids.
		localToasts += 1
		player:SetAttribute("ToastText", message)
		player:SetAttribute("ToastId", -localToasts)
	end
	return ok
end

local function questCard(q, order)
	local c = card(order, q.status == "done" and Color3.fromRGB(205, 200, 176) or CARD)
	local head = q.name
	if q.status == "done" then
		head ..= "  ✓"
	end
	line(c, head, 18, INK, Enum.Font.GothamBold, 1)
	line(c, ("%s · %s"):format(q.giver, q.region), 12, SOFT, Enum.Font.GothamMedium, 2)
	if q.status == "waiting" then
		line(c, ("Opens when %s is built."):format(q.region), 14, SOFT, Enum.Font.GothamMedium, 3)
	elseif q.status == "locked" then
		line(c, "First finish: " .. table.concat(q.needs, ", "), 14, SOFT, Enum.Font.GothamMedium, 3)
	else
		line(c, q.blurb, 14, INK, Enum.Font.Gotham, 3)
		if q.status == "active" then
			for i, step in q.steps do
				local mark = step.done and "✓" or step.current and "▶" or "○"
				local text = ("%s  %s"):format(mark, step.text)
				if step.n and step.count then
					text ..= (" (%d/%d)"):format(step.n, step.count)
				end
				if step.when then
					text ..= "  · " .. step.when
				end
				local color = step.done and SOFT or step.current and INK or MUTED
				line(c, text, 14, color, step.current and Enum.Font.GothamBold or Enum.Font.Gotham, 3 + i)
			end
		end
	end
	if q.reward ~= "" then
		line(c, "Reward: " .. q.reward, 13, GREEN, Enum.Font.GothamBold, 50)
	end
	if q.status == "active" then
		local track = button(c, "Track", GOLD)
		track.LayoutOrder = 60
		track.Size = UDim2.fromOffset(80, 26)
		track.TextSize = 13
		track.Activated:Connect(function()
			act("track", q.id)
		end)
	end
end

local function showQuests(rituals)
	local order = 0
	-- Active first, then the ones waiting on something, then finished.
	for _, wanted in { "active", "locked", "waiting", "done" } do
		for _, q in data.quests do
			if q.status == wanted and q.ritual == rituals then
				order += 1
				questCard(q, order)
			end
		end
	end
	if order == 0 then
		line(scroll, "Nothing here yet.", 14, SOFT)
	end
end

local function showBounties()
	line(
		scroll,
		"Three jobs a day, the same for everyone. New ones at midnight UTC.",
		14,
		SOFT,
		Enum.Font.GothamMedium,
		0
	)
	for i, b in data.bounties do
		local c = card(i)
		line(c, (b.done and "✓  " or "") .. b.text, 17, INK, Enum.Font.GothamBold, 1)
		line(c, ("%d / %d"):format(b.n, b.count), 14, SOFT, Enum.Font.GothamMedium, 2)
		line(c, ("Reward: $%d"):format(b.cash), 13, GREEN, Enum.Font.GothamBold, 3)
	end
end

local function showRelics()
	local found = 0
	for _, r in data.relics do
		if r.found then
			found += 1
		end
	end
	line(
		scroll,
		("%d of %d found. Rituals and hidden quests give these."):format(found, #data.relics),
		14,
		SOFT,
		Enum.Font.GothamMedium,
		0
	)
	for i, r in data.relics do
		local c = card(i, r.found and CARD or Color3.fromRGB(176, 166, 140))
		line(c, r.name, 17, r.found and INK or SOFT, Enum.Font.GothamBold, 1)
		line(c, r.blurb, 14, r.found and INK or SOFT, r.found and Enum.Font.Gotham or Enum.Font.GothamMedium, 2)
	end
end

local function showRewards()
	if #data.gear == 0 then
		line(
			scroll,
			"Quest gear, quest gloves and quest trucks show up here once you earn them. None of it is sold anywhere.",
			14,
			SOFT
		)
		return
	end
	for i, g in data.gear do
		local c = card(i)
		line(c, g.name, 17, INK, Enum.Font.GothamBold, 1)
		line(c, g.blurb, 14, INK, Enum.Font.Gotham, 2)
		if g.kind == "gloves" then
			local b = button(c, g.wearing and "Wearing" or "Wear", g.wearing and MUTED or GREEN)
			b.LayoutOrder = 3
			b.Size = UDim2.fromOffset(90, 28)
			b.Activated:Connect(function()
				if act("wear", g.id) then
					task.wait(0.2)
					render(true)
				end
			end)
		elseif g.kind == "truck" then
			local b = button(c, "Call truck", GREEN)
			b.LayoutOrder = 3
			b.Size = UDim2.fromOffset(110, 28)
			b.Activated:Connect(function()
				act("truck", g.id)
			end)
		end
	end
end

render = function(refetch)
	if refetch or not data then
		local ok, result = pcall(function()
			return getRemote:InvokeServer()
		end)
		data = ok and result or nil
	end
	for _, child in scroll:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	for name, b in tabButtons do
		b.BackgroundColor3 = name == tab and GOLD or MUTED
	end
	if not data then
		line(scroll, "Pick a save first.", 15, SOFT)
		return
	end
	if tab == "Quests" then
		showQuests(false)
	elseif tab == "Rituals" then
		showQuests(true)
	elseif tab == "Bounties" then
		showBounties()
	elseif tab == "Mystery items" then
		showRelics()
	else
		showRewards()
	end
end

local function toggle()
	panel.Visible = not panel.Visible
	if panel.Visible then
		render(true)
	end
end

close.Activated:Connect(function()
	panel.Visible = false
end)
tracker.Activated:Connect(toggle)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not gameProcessed and input.KeyCode == Enum.KeyCode.Q then
		toggle()
	end
end)
changedRemote.OnClientEvent:Connect(function()
	if panel.Visible then
		render(true)
	else
		data = nil
	end
end)

-- Quest spots in the world: a marker and a working prompt only where one of your quests needs you. ------------------

local function activeSpots()
	local set = {}
	for id in string.gmatch(player:GetAttribute("QuestSpots") or "", "[^,]+") do
		set[id] = true
	end
	return set
end

local function refreshSpot(base, set)
	local on = set[base:GetAttribute("SpotId")] == true
	local marker = base:FindFirstChild("QuestMarker")
	if marker then
		marker.Enabled = on
	end
	local prompt = base:FindFirstChild("QuestPrompt")
	if prompt then
		prompt.Enabled = on
	end
end

local function refreshSpots()
	local set = activeSpots()
	for _, base in CollectionService:GetTagged("QuestSpot") do
		refreshSpot(base, set)
	end
end

player:GetAttributeChangedSignal("QuestSpots"):Connect(refreshSpots)
CollectionService:GetInstanceAddedSignal("QuestSpot"):Connect(function(base)
	-- The marker and prompt may replicate a moment after the tagged part.
	task.delay(0.5, function()
		if base.Parent then
			refreshSpot(base, activeSpots())
		end
	end)
	refreshSpot(base, activeSpots())
end)
refreshSpots()

print("[Needlewood] quest log ready (Q)")
