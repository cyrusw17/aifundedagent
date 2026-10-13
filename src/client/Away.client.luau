--!nonstrict
-- The "While you were away" card (CEO "Addiction push" H1). When your farm loads, the server pays what your line
-- sorted while you were offline (Land.luau mailbox, Shared/Away.luau) and sets AwayCash, AwayBales, AwayNeedles and
-- AwaySeconds on you; they stay nil when nothing was paid. The money is already in your wallet, so COLLECT only
-- closes the card and clears the attributes on this screen. Nothing here decides or pays anything.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local UI = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UI")
local Kit = require(UI:WaitForChild("Kit"))
local Menus = require(UI:WaitForChild("Menus"))
local Sounds = require(ReplicatedStorage.Shared:WaitForChild("Config"):WaitForChild("Sounds"))
local C, F, T = Kit.Theme.Colors, Kit.Theme.Fonts, Kit.Theme.Text

local player = Players.LocalPlayer
local ATTRIBUTES = { "AwayCash", "AwayBales", "AwayNeedles", "AwaySeconds" }

local gui = Kit.screen("NeedlewoodAway", 7)
local panel, body = Kit.panel(gui, { title = "WHILE YOU WERE AWAY", name = "Away", width = 360, height = 250 })
panel.Visible = false

local cash = Kit.label(body, "", { size = 34, font = F.Title, color = C.Cash, align = "center", wrap = false })
cash.Size = UDim2.new(1, 0, 0, 44)
cash.Position = UDim2.fromOffset(0, 4)

local sorted = Kit.label(body, "", { size = T.Body, font = F.Bold, color = C.Ink, align = "center" })
sorted.Size = UDim2.new(1, 0, 0, 40)
sorted.Position = UDim2.fromOffset(0, 52)

local needles = Kit.label(body, "", { size = T.Small + 1, color = C.InkSoft, align = "center" })
needles.Size = UDim2.new(1, 0, 0, 22)
needles.Position = UDim2.fromOffset(0, 96)

local collect = Kit.button(body, "COLLECT", "go", UDim2.fromOffset(160, 40))
collect.AnchorPoint = Vector2.new(0.5, 1)
collect.Position = UDim2.new(0.5, 0, 1, -4)

-- "3.5 hours" or "12 minutes".
local function span(seconds)
	local hours = seconds / 3600
	if hours >= 1 then
		local shown = ("%.1f"):format(hours):gsub("%.0$", "")
		return ("%s hour%s"):format(shown, shown == "1" and "" or "s")
	end
	local minutes = math.max(1, math.floor(seconds / 60))
	return ("%d minute%s"):format(minutes, minutes == 1 and "" or "s")
end

local function chime()
	local def = Sounds.CashRegister
	if not def then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = def.id
	sound.Volume = def.volume * (player:GetAttribute("SettingEffects") or 1)
	sound.PlaybackSpeed = def.pitch or 1
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
end

local function fill()
	local paid = player:GetAttribute("AwayCash") or 0
	local bales = player:GetAttribute("AwayBales") or 0
	local found = player:GetAttribute("AwayNeedles") or 0
	local seconds = player:GetAttribute("AwaySeconds") or 0
	cash.Text = "+" .. Kit.money(paid)
	sorted.Text = ("Your line sorted %d bale%s in %s."):format(bales, bales == 1 and "" or "s", span(seconds))
	needles.Text = found > 0 and ("%d needle%s waiting in your bin"):format(found, found == 1 and "" or "s") or ""
end

Menus.register("Away", function(open)
	panel.Visible = open
	if open then
		fill()
	end
end)

collect.Activated:Connect(function()
	for _, name in ATTRIBUTES do
		player:SetAttribute(name, nil)
	end
	Menus.close()
end)

-- The server adds each farm's pay one attribute at a time (two farms add twice), so wait for it to settle, then
-- open the card once. Later changes while it is open just refresh the numbers.
local pending = false
local function arrived()
	if Menus.current() == "Away" then
		fill()
		return
	end
	if pending then
		return
	end
	pending = true
	task.delay(1.5, function()
		pending = false
		if (player:GetAttribute("AwayCash") or 0) > 0 or (player:GetAttribute("AwayBales") or 0) > 0 then
			Menus.open("Away")
			chime()
		end
	end)
end
for _, name in ATTRIBUTES do
	player:GetAttributeChangedSignal(name):Connect(function()
		if player:GetAttribute(name) ~= nil then
			arrived()
		end
	end)
end
if player:GetAttribute("AwayCash") ~= nil then
	arrived()
end
