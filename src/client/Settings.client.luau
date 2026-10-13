--!nonstrict
-- The settings page (⚙ under the HUD): sound volume, UI size, shadows, floating labels, replay the tutorial and the
-- list of controls. Values are saved with the save slot by the server (Settings.luau) and come back as "Setting<Key>"
-- player attributes; this script applies them on this screen.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local UI = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UI")
local Kit = require(UI:WaitForChild("Kit"))
local Menus = require(UI:WaitForChild("Menus"))

local C, F, T = Kit.Theme.Colors, Kit.Theme.Fonts, Kit.Theme.Text
local player = Players.LocalPlayer
local setRemote = ReplicatedStorage:WaitForChild("Settings"):WaitForChild("Set")

-- Applying -----------------------------------------------------------------------------------------------------------

-- Every sound in the game plays through this group, so one slider sets them all.
local effects = Instance.new("SoundGroup")
effects.Name = "Effects"
effects.Parent = SoundService

local function claim(sound)
	if sound:IsA("Sound") and not sound.SoundGroup then
		sound.SoundGroup = effects
	end
end
for _, root in { Workspace, SoundService, player:WaitForChild("PlayerGui") } do
	for _, d in root:GetDescendants() do
		claim(d)
	end
	root.DescendantAdded:Connect(claim)
end

-- Floating name tags and signs (WorldLabel.billboard names them "WorldLabel"). Streaming adds and drops them as you
-- move, so new ones are caught as they arrive.
local function setLabel(gui)
	if gui:IsA("BillboardGui") and gui.Name == "WorldLabel" then
		gui.Enabled = player:GetAttribute("SettingLabels") ~= false
	end
end
Workspace.DescendantAdded:Connect(setLabel)

local function apply()
	effects.Volume = player:GetAttribute("SettingEffects") or 1
	Lighting.GlobalShadows = player:GetAttribute("SettingShadows") ~= false
end
local function applyLabels()
	for _, d in Workspace:GetDescendants() do
		setLabel(d)
	end
end
player:GetAttributeChangedSignal("SettingEffects"):Connect(apply)
player:GetAttributeChangedSignal("SettingShadows"):Connect(apply)
player:GetAttributeChangedSignal("SettingLabels"):Connect(applyLabels)
apply()

-- The page -----------------------------------------------------------------------------------------------------------

local gui = Kit.screen("NeedlewoodSettings", 7)
local panel, body = Kit.panel(gui, {
	title = "SETTINGS",
	name = "Settings",
	width = 420,
	height = 520,
	onClose = function()
		Menus.close()
	end,
})
panel.Visible = false
local list = Kit.list(body, 8)

local order = 0
local function row(title, height)
	order += 1
	local card = Kit.card(list, height or 52)
	card.LayoutOrder = order
	local name = Kit.label(card, title, { size = T.Body, font = F.Bold, color = C.Ink, wrap = false })
	name.Position = UDim2.fromOffset(12, 0)
	name.Size = UDim2.new(0.45, -12, 1, 0)
	return card, name
end

-- A row of choice buttons on the right of a card. options: { { label, value }, ... }
local refreshers = {}
local function choices(card, key, options)
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(1, 0.5)
	holder.Position = UDim2.new(1, -10, 0.5, 0)
	holder.Size = UDim2.new(0.55, -10, 0, 32)
	holder.BackgroundTransparency = 1
	holder.Parent = card
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.Padding = UDim.new(0, 4)
	layout.Parent = holder
	local buttons = {}
	for i, option in options do
		local b = Kit.button(holder, option[1], "plain", UDim2.new(1 / #options, -4, 1, 0))
		b.LayoutOrder = i
		b.TextSize = T.Small
		b.Activated:Connect(function()
			setRemote:FireServer(key, option[2])
		end)
		buttons[i] = b
	end
	local attribute = "Setting" .. key:sub(1, 1):upper() .. key:sub(2)
	local function refresh()
		local value = player:GetAttribute(attribute)
		for i, option in options do
			Kit.setStyle(buttons[i], option[2] == value and "picked" or "plain")
		end
	end
	player:GetAttributeChangedSignal(attribute):Connect(refresh)
	table.insert(refreshers, refresh)
	refresh()
end

choices(row("Sound effects"), "effects", { { "OFF", 0 }, { "LOW", 0.35 }, { "MID", 0.7 }, { "FULL", 1 } })
choices(row("Screen size"), "uiSize", { { "SMALL", "small" }, { "NORMAL", "normal" }, { "LARGE", "large" } })
choices(row("Shadows"), "shadows", { { "ON", true }, { "OFF", false } })
choices(row("Floating labels"), "labels", { { "ON", true }, { "OFF", false } })
-- Comfort (Hay thread): ToolRepeat.client and Throw.client read these.
choices(row("Hold click to keep scooping"), "holdScoop", { { "ON", true }, { "OFF", false } })
choices(row("Carry a bale"), "holdCarry", { { "TOGGLE", false }, { "HOLD F", true } })
choices(row("Throw button (phone)"), "bigThrow", { { "NORMAL", false }, { "BIG", true } })

local help = row("Tutorial")
local replay = Kit.button(help, "PLAY AGAIN", "wood", UDim2.fromOffset(130, 32))
replay.AnchorPoint = Vector2.new(1, 0.5)
replay.Position = UDim2.new(1, -10, 0.5, 0)
replay.TextSize = T.Small
replay.Activated:Connect(function()
	Menus.close()
	Menus.event("Help"):Fire()
end)

local CONTROLS = {
	{ "Click a bale / hay", "Use your shovel or rake" },
	{ "F", "Lift a bale, or pick up thatch" },
	{ "Click or G", "Put down what you carry" },
	{ "E", "Talk, buy, drive, hitch" },
	{ "1, 2", "Shovel, rake" },
	{ "M", "Map" },
	{ "B", "Shop" },
	{ "K", "Collection book" },
	{ "Q", "Quest log" },
	{ "Esc", "Close a page" },
	{ "Build mode", "R turn, X remove, Z undo, M move, C copy, V paste" },
}
local controls, controlsTitle = row("Controls", 34 + #CONTROLS * 20)
controlsTitle.Size = UDim2.new(1, -24, 0, 32)
for i, def in CONTROLS do
	local key = Kit.label(controls, def[1], { size = T.Small, font = F.Bold, color = C.Wood, wrap = false })
	key.Position = UDim2.fromOffset(12, 12 + i * 20)
	key.Size = UDim2.new(0.38, -12, 0, 18)
	local what = Kit.label(controls, def[2], { size = T.Small, font = F.Body, color = C.Ink, wrap = false })
	what.Position = UDim2.new(0.38, 0, 0, 12 + i * 20)
	what.Size = UDim2.new(0.62, -12, 0, 18)
	what.TextTruncate = Enum.TextTruncate.AtEnd
end

Menus.register("Settings", function(open)
	panel.Visible = open
	if open then
		for _, refresh in refreshers do
			refresh()
		end
	end
end)
