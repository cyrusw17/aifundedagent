--!nonstrict
-- The collection book (BOOK under the HUD, or K). Four pages:
--   FINDS   every foreign object from a burst bale (Config/Finds), kept ones from the "Finds" attribute (Finds.luau)
--   NEEDLES every needle type (Config/Needles), found ones from "CodexNeedles" (Codex.luau)
--   HAY     every hay type (Config/Gloves HayTypes), broken-open ones from "CodexHay" (Codex.luau)
--   PLACES  every region and landmark (UI/DiscoveryList), found ones from "Discovered" (Discoveries.luau)
-- Found things show in full; the rest are dark shapes with a hint. A finished page shows its title.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = Shared:WaitForChild("UI")
local Config = Shared:WaitForChild("Config")
local Kit = require(UI:WaitForChild("Kit"))
local Menus = require(UI:WaitForChild("Menus"))
local FindsConfig = require(Config:WaitForChild("Finds"))
local NeedleTypes = require(Config:WaitForChild("Needles"))
local Gloves = require(Config:WaitForChild("Gloves"))
local HayLooks = require(Config:WaitForChild("HayLooks"))
local DiscoveryList = require(UI:WaitForChild("DiscoveryList"))

local C, F, T = Kit.Theme.Colors, Kit.Theme.Fonts, Kit.Theme.Text
local player = Players.LocalPlayer

-- Needle colors, matching LOOKS in Needle.luau (server-only), and whether they glow.
local NEEDLE_COLORS = {
	steel = { 150, 158, 166 },
	pine = { 96, 140, 84 },
	sand = { 214, 186, 120 },
	ice = { 170, 220, 240, true },
	bog = { 110, 128, 70 },
	coral = { 214, 120, 104 },
	brass = { 181, 148, 72 },
	obsidian = { 60, 40, 70, true },
	geode = { 170, 110, 220, true },
	cloud = { 240, 244, 255, true },
	phantom = { 120, 230, 210, true },
	cosmic = { 80, 70, 220, true },
}

local function counts(attribute)
	local out = {}
	for id, count in string.gmatch(player:GetAttribute(attribute) or "", "([%w_]+):(%d+)") do
		out[id] = tonumber(count)
	end
	return out
end
local function set(attribute)
	local out = {}
	for id in string.gmatch(player:GetAttribute(attribute) or "", "[^,]+") do
		out[id] = true
	end
	return out
end

-- Each page: entries { id, name, size, color, material, glow, lines(found) -> line1, line2 } and a title for
-- finishing it.
local PAGES = {}

do
	local items = table.clone(FindsConfig.Items)
	table.sort(items, function(a, b)
		return a.oneIn < b.oneIn
	end)
	local entries = {}
	for _, def in items do
		table.insert(entries, {
			id = def.id,
			name = def.name,
			size = Vector3.new(table.unpack(def.size)),
			color = Color3.fromRGB(table.unpack(def.color)),
			material = Enum.Material[def.material] or Enum.Material.SmoothPlastic,
			lines = function(found, count)
				if found then
					return ("You have %d"):format(count), ("Reward paid: %s"):format(Kit.money(def.reward))
				end
				return ("Rarity: 1 in %s bales"):format(Kit.money(def.oneIn):sub(2)),
					("Reward: %s"):format(Kit.money(def.reward))
			end,
		})
	end
	table.insert(PAGES, {
		tab = "FINDS",
		intro = "Odd things turn up when a bale bursts. Click one to keep it. The first of each kind pays a finder's reward.",
		entries = entries,
		attribute = "Finds",
		read = function()
			return counts("Finds")
		end,
		title = "Treasure Hunter",
	})
end

do
	local entries = {}
	for _, def in NeedleTypes do
		local look = NEEDLE_COLORS[def.id] or NEEDLE_COLORS.steel
		table.insert(entries, {
			id = def.id,
			name = def.name .. " needle",
			size = Vector3.new(0.12, 0.12, 1.6),
			color = Color3.fromRGB(look[1], look[2], look[3]),
			material = look[4] and Enum.Material.Neon or Enum.Material.Metal,
			lines = function(found)
				if found then
					return ("From %s"):format(def.map), ("Sorted: %s each"):format(Kit.money(def.sortedValue))
				end
				return ("Hidden in %s hay"):format(def.map), ("Worth %s sorted"):format(Kit.money(def.sortedValue))
			end,
		})
	end
	table.insert(PAGES, {
		tab = "NEEDLES",
		intro = "One needle type per region's hay. Find one anywhere (a bale, a sorter, the rake) to fill its page.",
		entries = entries,
		attribute = "CodexNeedles",
		read = function()
			return set("CodexNeedles")
		end,
		title = "Needle Master",
	})
end

do
	local ids = {}
	for id in Gloves.HayTypes do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		local ta, tb = Gloves.HayTypes[a].tier, Gloves.HayTypes[b].tier
		if ta ~= tb then
			return ta < tb
		end
		return Gloves.HayTypes[a].weight < Gloves.HayTypes[b].weight
	end)
	local entries = {}
	for _, id in ids do
		local def = Gloves.HayTypes[id]
		local look = HayLooks[id] or HayLooks.meadow
		local rgb = look.colors[1]
		table.insert(entries, {
			id = id,
			name = def.name,
			size = Vector3.new(4.6, 2.6, 3.2), -- the canonical bale
			color = Color3.fromRGB(rgb[1], rgb[2], rgb[3]),
			material = Enum.Material.Fabric,
			lines = function(found)
				local tier = def.tier > 0 and ("Glove tier %d"):format(def.tier) or "Any gloves"
				if found then
					return ("%s · %s"):format(def.map, tier), ("%.1fx heavier than meadow"):format(def.weight)
				end
				return ("Grows in %s"):format(def.map), tier
			end,
		})
	end
	table.insert(PAGES, {
		tab = "HAY",
		intro = "Every region grows its own hay. Break a bale of one open to fill its page.",
		entries = entries,
		attribute = "CodexHay",
		read = function()
			return set("CodexHay")
		end,
		title = "Hay Connoisseur",
	})
end

do
	local entries = {}
	for _, d in DiscoveryList.all() do
		local region = d.kind == "region"
		table.insert(entries, {
			id = d.id,
			name = d.name,
			-- A little patch of land for a region, a standing stone for a landmark.
			size = region and Vector3.new(3, 0.6, 3) or Vector3.new(0.8, 2.4, 0.8),
			color = region and Color3.fromRGB(110, 132, 82) or Color3.fromRGB(150, 140, 120),
			material = region and Enum.Material.Grass or Enum.Material.Slate,
			lines = function(found)
				if found then
					return region and "Region visited" or ("Landmark near %s"):format(d.near or "the isles"),
						("Finder's pay: %s"):format(Kit.money(d.reward))
				end
				return region and "A region of the isles" or ("Somewhere near %s"):format(d.near or "the isles"),
					("Pays %s the first time"):format(Kit.money(d.reward))
			end,
		})
	end
	table.insert(PAGES, {
		tab = "PLACES",
		intro = "Every region and landmark of the Stitched Isles. Your first visit to each pays out and stamps your map.",
		entries = entries,
		attribute = "Discovered",
		read = function()
			return DiscoveryList.found(player)
		end,
		title = "Isle Explorer",
	})
end

-- The panel ---------------------------------------------------------------------------------------------------------

local gui = Kit.screen("NeedlewoodBook", 6)
local panel, body, title = Kit.panel(gui, {
	title = "COLLECTION BOOK",
	name = "Book",
	width = 580,
	height = 520,
	onClose = function()
		Menus.close()
	end,
})
panel.Visible = false

local pageIndex = 1
local intro = Kit.label(body, "", { size = T.Small, font = F.Body, color = C.InkSoft, height = 34 })
intro.Position = UDim2.fromOffset(0, 38)
intro.TextWrapped = true
local banner = Kit.label(body, "", { size = T.Small, font = F.Bold, color = C.Green, wrap = false, align = "center" })
banner.Position = UDim2.fromOffset(0, 72)
banner.Size = UDim2.new(1, 0, 0, 18)

local grid = Instance.new("ScrollingFrame")
grid.Position = UDim2.fromOffset(0, 94)
grid.Size = UDim2.new(1, 0, 1, -94)
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
local gridPad = Instance.new("UIPadding")
gridPad.PaddingRight = UDim.new(0, 8)
gridPad.Parent = grid

-- A small 3D look at the thing, turning in a ViewportFrame.
local function preview(parent, entry)
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
	local part = Instance.new("Part")
	part.Anchored = true
	part.Size = entry.size
	part.Color = entry.color
	part.Material = entry.material
	part.CFrame = CFrame.Angles(math.rad(20), math.rad(35), 0)
	part.Parent = view
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	local reach = entry.size.Magnitude * 2.2
	camera.CFrame = CFrame.lookAt(Vector3.new(0, reach * 0.35, reach), Vector3.zero)
	camera.Parent = view
	view.CurrentCamera = camera
	return view, part
end

local cards = {}
local function build()
	for _, card in cards do
		card.frame:Destroy()
	end
	table.clear(cards)
	for i, entry in PAGES[pageIndex].entries do
		local frame = Kit.card(grid, 176)
		frame.LayoutOrder = i
		local view, part = preview(frame, entry)
		local function text(y, color, font)
			local l = Kit.label(
				frame,
				"",
				{ size = T.Small, font = font or F.Medium, color = color, wrap = false, align = "center" }
			)
			l.Position = UDim2.fromOffset(6, y)
			l.Size = UDim2.new(1, -12, 0, 18)
			l.TextTruncate = Enum.TextTruncate.AtEnd
			return l
		end
		local name = text(104, C.Ink, F.Bold)
		name.TextSize = T.Body
		table.insert(cards, {
			entry = entry,
			frame = frame,
			view = view,
			part = part,
			name = name,
			line1 = text(126, C.InkSoft),
			line2 = text(146, C.Green),
		})
	end
end

local function render()
	local page = PAGES[pageIndex]
	local have = page.read()
	local found = 0
	for _, card in cards do
		local value = have[card.entry.id]
		local isFound = value ~= nil and value ~= false and value ~= 0
		local line1, line2 = card.entry.lines(isFound, value)
		card.line1.Text = line1
		card.line2.Text = line2
		if isFound then
			found += 1
			card.name.Text = card.entry.name
			card.view.ImageColor3 = Color3.new(1, 1, 1)
			card.line2.TextColor3 = C.Green
		else
			card.name.Text = "???"
			card.view.ImageColor3 = Color3.new(0, 0, 0)
			card.line2.TextColor3 = C.Wood
		end
	end
	intro.Text = page.intro
	local total = #page.entries
	banner.Text = found >= total and ("PAGE COMPLETE: %s"):format(page.title)
		or ("%d of %d found. Finish the page for the title %s."):format(found, total, page.title)
	banner.TextColor3 = found >= total and C.Green or C.InkSoft
	title.Text = ("COLLECTION BOOK  ·  %s %d / %d"):format(page.tab, found, total)
end

local tabNames = {}
for _, page in PAGES do
	table.insert(tabNames, page.tab)
end
local _, selectTab = Kit.tabs(body, tabNames, function(index)
	pageIndex = index
	build()
	render()
end)

for _, page in PAGES do
	player:GetAttributeChangedSignal(page.attribute):Connect(function()
		if panel.Visible and PAGES[pageIndex] == page then
			render()
		end
	end)
end

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
		selectTab(pageIndex)
		spin()
	end
end)
