--!nonstrict
-- The collection book (BOOK under the HUD, or K): every foreign object that can tumble out of a burst bale
-- (Config/Finds), with the ones you have kept shown in full and the rest as dark shapes. Reads the "Finds" player
-- attribute ("boot:2,ring:1") that Finds.luau keeps.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = Shared:WaitForChild("UI")
local Kit = require(UI:WaitForChild("Kit"))
local Menus = require(UI:WaitForChild("Menus"))
local FindsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Finds"))

local C, F, T = Kit.Theme.Colors, Kit.Theme.Fonts, Kit.Theme.Text
local player = Players.LocalPlayer

local function kept()
	local counts = {}
	for id, count in string.gmatch(player:GetAttribute("Finds") or "", "([%w_]+):(%d+)") do
		counts[id] = tonumber(count)
	end
	return counts
end

local gui = Kit.screen("NeedlewoodBook", 6)
local panel, body, title = Kit.panel(gui, {
	title = "COLLECTION BOOK",
	name = "Book",
	width = 560,
	height = 500,
	onClose = function()
		Menus.close()
	end,
})
panel.Visible = false

local intro = Kit.label(
	body,
	"Odd things turn up when a bale bursts. Click one to keep it. The first of each kind pays a finder's reward.",
	{ size = T.Small, font = F.Body, color = C.InkSoft, height = 34 }
)
intro.TextWrapped = true
local grid = Instance.new("ScrollingFrame")
grid.Position = UDim2.fromOffset(0, 42)
grid.Size = UDim2.new(1, 0, 1, -42)
grid.BackgroundTransparency = 1
grid.BorderSizePixel = 0
grid.ScrollBarThickness = 6
grid.ScrollBarImageColor3 = C.WoodLight
grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
grid.CanvasSize = UDim2.new()
grid.Parent = body
local layout = Instance.new("UIGridLayout")
layout.CellSize = UDim2.new(1 / 3, -8, 0, 176)
layout.CellPadding = UDim2.fromOffset(8, 8)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = grid

-- A small 3D look at the find: its part (size, color, material from the config) turning in a ViewportFrame.
local function preview(parent, def)
	local view = Instance.new("ViewportFrame")
	view.Position = UDim2.fromOffset(8, 8)
	view.Size = UDim2.new(1, -16, 0, 92)
	view.BackgroundColor3 = C.CardDim
	view.BorderSizePixel = 0
	view.Ambient = Color3.fromRGB(170, 160, 140)
	view.LightColor = Color3.fromRGB(255, 244, 220)
	view.LightDirection = Vector3.new(-1, -1, -0.6)
	view.Parent = parent
	Kit.corner(view, 6)
	local size = Vector3.new(table.unpack(def.size))
	local part = Instance.new("Part")
	part.Anchored = true
	part.Size = size
	part.Color = Color3.fromRGB(table.unpack(def.color))
	part.Material = Enum.Material[def.material] or Enum.Material.SmoothPlastic
	part.CFrame = CFrame.Angles(math.rad(20), math.rad(35), 0)
	part.Parent = view
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	local reach = size.Magnitude * 2.2
	camera.CFrame = CFrame.lookAt(Vector3.new(0, reach * 0.35, reach), Vector3.zero)
	camera.Parent = view
	view.CurrentCamera = camera
	return view, part
end

local function oneIn(n)
	return "1 in " .. Kit.money(n):sub(2)
end

local cards = {}
local items = table.clone(FindsConfig.Items)
table.sort(items, function(a, b)
	return a.oneIn < b.oneIn
end)
for i, def in items do
	local card = Kit.card(grid, 176)
	card.LayoutOrder = i
	local view, part = preview(card, def)
	local name = Kit.label(card, "", { size = T.Body, font = F.Bold, color = C.Ink, wrap = false, align = "center" })
	name.Position = UDim2.fromOffset(6, 104)
	name.Size = UDim2.new(1, -12, 0, 20)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	local line1 =
		Kit.label(card, "", { size = T.Small, font = F.Medium, color = C.InkSoft, wrap = false, align = "center" })
	line1.Position = UDim2.fromOffset(6, 126)
	line1.Size = UDim2.new(1, -12, 0, 18)
	local line2 =
		Kit.label(card, "", { size = T.Small, font = F.Medium, color = C.Green, wrap = false, align = "center" })
	line2.Position = UDim2.fromOffset(6, 146)
	line2.Size = UDim2.new(1, -12, 0, 18)
	cards[def.id] = { def = def, view = view, part = part, name = name, line1 = line1, line2 = line2 }
end

local function render()
	local counts = kept()
	local found = 0
	for _, card in cards do
		local def = card.def
		local count = counts[def.id] or 0
		if count > 0 then
			found += 1
			card.name.Text = def.name
			card.part.Color = Color3.fromRGB(table.unpack(def.color))
			card.view.ImageColor3 = Color3.new(1, 1, 1)
			card.line1.Text = ("You have %d"):format(count)
			card.line2.Text = ("Reward paid: %s"):format(Kit.money(def.reward))
			card.line2.TextColor3 = C.Green
		else
			card.name.Text = "???"
			card.view.ImageColor3 = Color3.new(0, 0, 0)
			card.line1.Text = ("Rarity: %s bales"):format(oneIn(def.oneIn))
			card.line2.Text = ("Reward: %s"):format(Kit.money(def.reward))
			card.line2.TextColor3 = C.Wood
		end
	end
	title.Text = ("COLLECTION BOOK  ·  %d / %d"):format(found, #items)
end
player:GetAttributeChangedSignal("Finds"):Connect(function()
	if panel.Visible then
		render()
	end
end)

-- Spin the previews while the book is open.
local spinning = false
local function spin()
	if spinning then
		return
	end
	spinning = true
	task.spawn(function()
		local angle = 0
		while panel.Visible do
			angle += math.rad(2)
			for _, card in cards do
				card.part.CFrame = CFrame.Angles(math.rad(20), angle, 0)
			end
			task.wait(1 / 30)
		end
		spinning = false
	end)
end

Menus.register("Book", function(open)
	panel.Visible = open
	if open then
		render()
		spin()
	end
end)
