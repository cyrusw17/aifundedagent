--!nonstrict
-- The quest log (Q, or click the quest card under the menu buttons), the quest card with the clock, and the quest
-- markers in the world. The server decides every step (src/server/Services/Quests.luau); this script only shows it.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = Shared:WaitForChild("UI")
local Kit = require(UI:WaitForChild("Kit"))
local Menus = require(UI:WaitForChild("Menus"))
local Waypoint = require(UI:WaitForChild("Waypoint"))
local Places = require(UI:WaitForChild("Places"))
local Hud = require(UI:WaitForChild("Hud"))

local remotes = ReplicatedStorage:WaitForChild("Quests")
local getRemote = remotes:WaitForChild("Get")
local actionRemote = remotes:WaitForChild("Action")
local changedRemote = remotes:WaitForChild("Changed")

local Theme = Kit.Theme
local C, F, T = Theme.Colors, Theme.Fonts, Theme.Text
local player = Players.LocalPlayer
local GOLD = Color3.fromRGB(255, 214, 120)

local gui = Kit.screen("NeedlewoodQuests", 5)

-- A label that grows to fit its text, for lists.
local function line(parent, text, size, color, font, order)
	local label = Kit.label(parent, text, { size = size, font = font, color = color, auto = true })
	label.Size = UDim2.new(1, 0, 0, 0)
	label.LayoutOrder = order or 0
	return label
end

local function vlist(parent, gap)
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, gap or 3)
	layout.Parent = parent
	return layout
end

local localToasts = 0
local function toast(message)
	-- Shown in the HUD toast (Main.client.luau watches ToastId). Negative ids never collide with the server's.
	localToasts += 1
	player:SetAttribute("ToastText", message)
	player:SetAttribute("ToastId", -localToasts)
end

local function act(kind, id)
	local ok, message = actionRemote:InvokeServer(kind, id)
	if message then
		toast(message)
	end
	return ok
end

-- Quest card: the clock and the quest you are on, last in the HUD column under the menu buttons (UI/Hud.luau).
-- Click it for the log; GO drops a waypoint on where the step sends you. -------------------------------------------

local card = Instance.new("TextButton")
card.Name = "QuestCard"
card.Text = ""
card.AutoButtonColor = false
card.LayoutOrder = Hud.Order.Extra
card.Size = UDim2.fromOffset(230, 0)
card.AutomaticSize = Enum.AutomaticSize.Y
card.BackgroundColor3 = C.Wood
card.BackgroundTransparency = 0.1
card.Parent = Hud.column()
Kit.corner(card, 10)
Kit.stroke(card, C.Ink, 1.5)
Kit.pad(card, 8)
vlist(card, 2)

local clockLabel = line(card, "", T.Small, C.Cream, F.Bold, 1)
local trackName = line(card, "", T.Body, GOLD, F.Bold, 2)
local trackStep = line(card, "", T.Small, C.Cream, F.Body, 3)
local cardRow = Instance.new("Frame")
cardRow.BackgroundTransparency = 1
cardRow.Size = UDim2.new(1, 0, 0, 24)
cardRow.LayoutOrder = 4
cardRow.Parent = card
local hint = Kit.label(cardRow, "Q: quest log", { size = T.Small, font = F.Medium, color = C.Hay, wrap = false })
hint.Size = UDim2.new(1, -60, 1, 0)
local goButton = Kit.button(cardRow, "GO", "go", UDim2.fromOffset(52, 24))
goButton.AnchorPoint = Vector2.new(1, 0)
goButton.Position = UDim2.new(1, 0, 0, 0)
goButton.TextSize = T.Small

local function refreshCard()
	local name = player:GetAttribute("QuestTrackName")
	trackName.Text = name or "No quest right now"
	trackStep.Text = player:GetAttribute("QuestTrackStep") or ""
	trackStep.Visible = name ~= nil
	goButton.Visible = player:GetAttribute("QuestTrackTarget") ~= nil or player:GetAttribute("QuestTrackPlace") ~= nil
	card.Visible = player:GetAttribute("SaveSlot") ~= nil
end
for _, attr in { "QuestTrackName", "QuestTrackStep", "QuestTrackTarget", "QuestTrackPlace", "SaveSlot" } do
	player:GetAttributeChangedSignal(attr):Connect(refreshCard)
end
refreshCard()

goButton.Activated:Connect(function()
	local target = player:GetAttribute("QuestTrackTarget")
	local place = player:GetAttribute("QuestTrackPlace")
	if typeof(target) == "Vector3" then
		Waypoint.set(target, player:GetAttribute("QuestTrackTargetName") or "Quest")
	elseif typeof(place) == "string" then
		local position = Places.get(place)
		if position then
			Waypoint.set(position, Places.name(place))
		else
			toast("Not sure where that is yet.")
		end
	end
end)

-- Same windows as Config/Quests.luau Time.
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

-- The log ------------------------------------------------------------------------------------------------------

local panel, body = Kit.panel(gui, {
	name = "QuestLog",
	title = "Quest log",
	width = 580,
	height = 540,
	onClose = function()
		Menus.close()
	end,
})

local TABS = { "Quests", "Rituals", "Bounties", "Mystery", "Rewards" }
local tab = 1
local data = nil
local render -- set below

local listHolder = Instance.new("Frame")
listHolder.BackgroundTransparency = 1
listHolder.Position = UDim2.fromOffset(0, 40)
listHolder.Size = UDim2.new(1, 0, 1, -40)
listHolder.Parent = body
local scroll = Kit.list(listHolder, 8)

local _, selectTab = Kit.tabs(body, TABS, function(index)
	tab = index
	if render then
		render(false)
	end
end)

local function entry(order, dim)
	local f = Kit.card(scroll, 0)
	f.AutomaticSize = Enum.AutomaticSize.Y
	f.BackgroundColor3 = dim and C.CardDim or C.Card
	f.LayoutOrder = order
	Kit.pad(f, 10)
	vlist(f, 3)
	return f
end

local function buttonRow(parent, order)
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 28)
	row.LayoutOrder = order
	row.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 6)
	layout.Parent = row
	return row
end

local function questEntry(q, order)
	local f = entry(order, q.status ~= "active")
	line(f, q.status == "done" and (q.name .. "  ✓") or q.name, T.Heading, C.Ink, F.Bold, 1)
	line(f, ("%s  ·  %s"):format(q.giver, q.region), T.Small, C.InkSoft, F.Medium, 2)
	if q.status == "waiting" then
		line(f, ("Opens when %s is built."):format(q.region), T.Body, C.InkSoft, F.Medium, 3)
	elseif q.status == "locked" then
		line(f, "First finish: " .. table.concat(q.needs, ", "), T.Body, C.InkSoft, F.Medium, 3)
	else
		line(f, q.blurb, T.Body, C.Ink, F.Body, 3)
		if q.status == "active" then
			for i, step in q.steps do
				local mark = step.done and "✓" or step.current and "▶" or "○"
				local text = ("%s  %s"):format(mark, step.text)
				if step.n and step.count then
					text ..= (" (%d/%d)"):format(step.n, step.count)
				end
				if step.when then
					text ..= "  ·  " .. step.when
				end
				line(f, text, T.Body, step.current and C.Ink or C.InkSoft, step.current and F.Bold or F.Body, 3 + i * 2)
				if step.hint then
					line(f, "Hint: " .. step.hint, T.Small + 1, C.InkSoft, F.Body, 4 + i * 2)
				end
			end
		end
	end
	if q.reward ~= "" then
		line(f, "Reward: " .. q.reward, T.Small + 1, C.Green, F.Bold, 50)
	end
	if q.status == "active" then
		local row = buttonRow(f, 60)
		local track = Kit.button(row, "Track", "wood", UDim2.fromOffset(84, 28))
		track.TextSize = T.Small + 1
		track.Activated:Connect(function()
			act("track", q.id)
		end)
		local target = q.targets and q.targets[1]
		if not target and q.place then
			local position = Places.get(q.place)
			target = position and { position = position, name = Places.name(q.place) }
		end
		if target then
			local go = Kit.button(row, "Show the way", "go", UDim2.fromOffset(120, 28))
			go.TextSize = T.Small + 1
			go.Activated:Connect(function()
				act("track", q.id)
				Waypoint.set(target.position, target.name)
				Menus.close()
			end)
		end
	end
end

local function showQuests(rituals)
	local order = 0
	-- Active first, then the ones waiting on something, then finished.
	for _, wanted in { "active", "locked", "waiting", "done" } do
		for _, q in data.quests do
			if q.status == wanted and q.ritual == rituals then
				order += 1
				questEntry(q, order)
			end
		end
	end
	if order == 0 then
		line(scroll, "Nothing here yet.", T.Body, C.InkSoft)
	end
end

local function showBounties()
	line(scroll, "Three jobs a day, the same for everyone. New ones at midnight UTC.", T.Body, C.InkSoft, F.Medium, 0)
	for i, b in data.bounties do
		local f = entry(i, b.done)
		line(f, (b.done and "✓  " or "") .. b.text, T.Heading, C.Ink, F.Bold, 1)
		line(f, ("%d / %d"):format(b.n, b.count), T.Body, C.InkSoft, F.Medium, 2)
		line(f, "Reward: " .. Kit.money(b.cash), T.Small + 1, C.Green, F.Bold, 3)
	end

	-- The daily streak: any finished bounty counts the day. A missed day pauses it, never resets it.
	local st = data.streak
	if st then
		local f = entry(10, false)
		line(f, ("Streak: %d day%s"):format(st.days, st.days == 1 and "" or "s"), T.Heading, C.Ink, F.Bold, 1)
		line(
			f,
			st.today and "Today counted. Come back tomorrow." or "Finish any bounty today to count it.",
			T.Body,
			st.today and C.Green or C.Ink,
			F.Medium,
			2
		)
		line(f, "Missing a day only pauses your streak. It never resets.", T.Small + 1, C.InkSoft, F.Body, 3)
		if st.nextMilestone then
			line(
				f,
				("Next: %s at %d days"):format(st.nextMilestone.name, st.nextMilestone.days),
				T.Small + 1,
				C.InkSoft,
				F.Medium,
				4
			)
		end
		if st.lucky then
			line(
				f,
				("Your lucky field today: %s. Bales there sometimes spill an extra needle."):format(st.lucky.region),
				T.Body,
				C.Ink,
				F.Bold,
				5
			)
			local row = buttonRow(f, 6)
			local go = Kit.button(row, "Show the way", "go", UDim2.fromOffset(120, 28))
			go.TextSize = T.Small + 1
			go.Activated:Connect(function()
				Waypoint.set(st.lucky.position, "Lucky field")
				Menus.close()
			end)
		elseif st.days < st.luckyFrom then
			line(
				f,
				("At %d days you get a lucky field each day."):format(st.luckyFrom),
				T.Small + 1,
				C.InkSoft,
				F.Body,
				5
			)
		end
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
		T.Body,
		C.InkSoft,
		F.Medium,
		0
	)
	for i, r in data.relics do
		local f = entry(i, not r.found)
		line(f, r.name, T.Heading, r.found and C.Ink or C.InkSoft, F.Bold, 1)
		line(f, r.blurb, T.Body, r.found and C.Ink or C.InkSoft, r.found and F.Body or F.Medium, 2)
	end
end

local function showRewards()
	if #data.gear == 0 then
		line(
			scroll,
			"Quest gear, quest gloves and quest trucks show up here once you earn them. None of it is sold anywhere.",
			T.Body,
			C.InkSoft
		)
		return
	end
	for i, g in data.gear do
		local f = entry(i, false)
		line(f, g.name, T.Heading, C.Ink, F.Bold, 1)
		line(f, g.blurb, T.Body, C.Ink, F.Body, 2)
		if g.kind == "gloves" then
			local row = buttonRow(f, 3)
			local b = Kit.button(
				row,
				g.wearing and "Wearing" or "Wear",
				g.wearing and "muted" or "go",
				UDim2.fromOffset(96, 28)
			)
			b.Activated:Connect(function()
				if act("wear", g.id) then
					task.wait(0.2)
					render(true)
				end
			end)
		elseif g.kind == "truck" then
			local row = buttonRow(f, 3)
			local b = Kit.button(row, "Call truck", "go", UDim2.fromOffset(110, 28))
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
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
	if not data then
		line(scroll, "Pick a save first.", T.Body, C.InkSoft)
		return
	end
	if tab == 1 then
		showQuests(false)
	elseif tab == 2 then
		showQuests(true)
	elseif tab == 3 then
		showBounties()
	elseif tab == 4 then
		showRelics()
	else
		showRewards()
	end
end

Menus.register("Quests", function(open)
	panel.Visible = open
	if open then
		task.spawn(render, true)
	end
end)
selectTab(1)

card.Activated:Connect(function()
	Menus.toggle("Quests")
end)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not gameProcessed and input.KeyCode == Enum.KeyCode.Q and player:GetAttribute("SaveSlot") then
		Menus.toggle("Quests")
	end
end)
changedRemote.OnClientEvent:Connect(function(kind, tabName)
	-- A bounty board (or anything else) can open the log at a tab.
	if kind == "open" then
		selectTab(table.find(TABS, tabName) or 1)
		Menus.open("Quests")
		return
	end
	if panel.Visible then
		render(true)
	else
		data = nil
	end
end)

-- Quest spots in the world: a marker and a working prompt only where one of your quests needs you. ----------------

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
	refreshSpot(base, activeSpots())
	-- The marker and prompt may replicate a moment after the tagged part.
	task.delay(0.5, function()
		if base.Parent then
			refreshSpot(base, activeSpots())
		end
	end)
end)
refreshSpots()
