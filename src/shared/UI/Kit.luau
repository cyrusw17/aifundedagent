--!nonstrict
-- Building blocks for every screen: panels with a wooden title bar, buttons, cards, lists and tabs, all in the
-- Rustic look from Theme.luau. Client only. Each function makes plain Roblox instances and returns them, so a
-- script can still move or tweak them after.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Theme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UI"):WaitForChild("Theme"))
local C, F, T = Theme.Colors, Theme.Fonts, Theme.Text

local Kit = {}
Kit.Theme = Theme

function Kit.corner(instance, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or Theme.Radius)
	c.Parent = instance
	return c
end

function Kit.stroke(instance, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color or C.Ink
	s.Thickness = thickness or Theme.Stroke
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = instance
	return s
end

function Kit.pad(instance, px)
	local p = Instance.new("UIPadding")
	local u = UDim.new(0, px or Theme.Pad)
	p.PaddingLeft, p.PaddingRight, p.PaddingTop, p.PaddingBottom = u, u, u, u
	p.Parent = instance
	return p
end

-- A ScreenGui for one feature. order sets what draws on top (bigger is higher).
function Kit.screen(name, order, ignoreInset)
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = ignoreInset == true
	gui.DisplayOrder = order or 0
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

-- Text. opts: size, font, color, align ("left" | "center" | "right"), wrap (default true), height.
function Kit.label(parent, text, opts)
	opts = opts or {}
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, opts.height or (opts.size or T.Body) + 6)
	label.Font = opts.font or F.Body
	label.TextSize = opts.size or T.Body
	label.TextColor3 = opts.color or C.Ink
	label.TextWrapped = opts.wrap ~= false
	label.TextXAlignment = opts.align == "center" and Enum.TextXAlignment.Center
		or opts.align == "right" and Enum.TextXAlignment.Right
		or Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Text = text or ""
	if opts.auto then
		label.AutomaticSize = Enum.AutomaticSize.Y
	end
	label.Parent = parent
	return label
end

Kit.ButtonStyles = {
	go = { bg = C.Green, fg = C.Cream },
	stop = { bg = C.Red, fg = C.Cream },
	wood = { bg = C.Wood, fg = C.Cream },
	plain = { bg = C.Card, fg = C.Ink },
	muted = { bg = C.Muted, fg = C.Cream },
	picked = { bg = C.Picked, fg = C.Ink },
	ink = { bg = C.Ink, fg = C.Cream },
}

function Kit.setStyle(button, style)
	local s = Kit.ButtonStyles[style] or Kit.ButtonStyles.go
	button.BackgroundColor3 = s.bg
	button.TextColor3 = s.fg
	button:SetAttribute("Style", style)
end

-- A button. style: go, stop, wood, plain, muted, picked, ink. size: UDim2.
function Kit.button(parent, text, style, size)
	local b = Instance.new("TextButton")
	b.Size = size or UDim2.fromOffset(120, 34)
	b.Font = F.Bold
	b.TextSize = T.Button
	b.Text = text or ""
	b.AutoButtonColor = true
	Kit.setStyle(b, style or "go")
	Kit.corner(b, 6)
	local s = Kit.stroke(b, C.Ink, 1.5)
	s.Transparency = 0.35
	b.Parent = parent
	return b
end

-- A card: a lighter block inside a panel. Returns the frame.
function Kit.card(parent, height)
	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, 0, 0, height or 80)
	card.BackgroundColor3 = C.Card
	card.BorderSizePixel = 0
	Kit.corner(card, 6)
	card.Parent = parent
	return card
end

-- A vertical scrolling list that grows with its children. Returns the ScrollingFrame.
function Kit.list(parent, gap)
	local list = Instance.new("ScrollingFrame")
	list.Size = UDim2.fromScale(1, 1)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = C.WoodLight
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, gap or 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	local p = Instance.new("UIPadding")
	p.PaddingRight = UDim.new(0, 10)
	p.Parent = list
	return list
end

-- UI size from Settings (the "SettingUiSize" player attribute) as a scale.
local UI_SIZES = { small = 0.85, normal = 1, large = 1.15 }
function Kit.userScale()
	local player = Players.LocalPlayer
	return player and UI_SIZES[player:GetAttribute("SettingUiSize") or "normal"] or 1
end

-- Shrinks a panel that is w x h pixels so it always fits the screen with a margin (and follows the UI size setting).
function Kit.fit(frame, w, h)
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	local function update()
		local camera = Workspace.CurrentCamera
		local view = camera and camera.ViewportSize or Vector2.new(1024, 768)
		local fits = math.min((view.X - 24) / w, (view.Y - 60) / h)
		scale.Scale = math.clamp(math.min(fits, Kit.userScale()), 0.45, 1.15)
	end
	update()
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	end
	if Players.LocalPlayer then
		Players.LocalPlayer:GetAttributeChangedSignal("SettingUiSize"):Connect(update)
	end
	return scale
end

-- A panel with a wooden title bar. opts: title, width, height, anchor (Vector2), position (UDim2), onClose
-- (shows an X button), subtitle. Returns panel, body (the area under the title bar), titleLabel.
function Kit.panel(parent, opts)
	opts = opts or {}
	local w, h = opts.width or 360, opts.height or 440
	local panel = Instance.new("Frame")
	panel.Name = opts.name or "Panel"
	panel.AnchorPoint = opts.anchor or Vector2.new(0.5, 0.5)
	panel.Position = opts.position or UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(w, h)
	panel.BackgroundColor3 = C.Paper
	panel.BorderSizePixel = 0
	panel.Active = true
	Kit.corner(panel, 10)
	Kit.stroke(panel, C.Ink, Theme.Stroke)
	panel.Parent = parent

	local bar = Instance.new("Frame")
	bar.Name = "TitleBar"
	bar.Size = UDim2.new(1, 0, 0, 40)
	bar.BackgroundColor3 = C.Wood
	bar.BorderSizePixel = 0
	Kit.corner(bar, 10)
	bar.Parent = panel
	-- Square off the bottom corners of the bar.
	local skirt = Instance.new("Frame")
	skirt.Size = UDim2.new(1, 0, 0, 10)
	skirt.Position = UDim2.new(0, 0, 1, -10)
	skirt.BackgroundColor3 = C.Wood
	skirt.BorderSizePixel = 0
	skirt.Parent = bar

	local title = Kit.label(bar, opts.title or "", { size = T.Title, font = F.Title, color = C.Cream, wrap = false })
	title.Position = UDim2.fromOffset(14, 0)
	title.Size = UDim2.new(1, opts.onClose and -60 or -28, 1, 0)
	title.TextTruncate = Enum.TextTruncate.AtEnd

	if opts.onClose then
		local close = Kit.button(bar, "X", "stop", UDim2.fromOffset(30, 30))
		close.AnchorPoint = Vector2.new(1, 0.5)
		close.Position = UDim2.new(1, -6, 0.5, 0)
		close.TextSize = 16
		close.Activated:Connect(opts.onClose)
	end

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(12, 48)
	body.Size = UDim2.new(1, -24, 1, -58)
	body.Parent = panel

	if opts.fit ~= false then
		Kit.fit(panel, w, h)
	end
	return panel, body, title
end

-- A row of tabs. names is a list of strings. onPick(index) runs when one is picked. Returns the row and a
-- select(index) function.
function Kit.tabs(parent, names, onPick)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 32)
	row.BackgroundTransparency = 1
	row.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	local buttons = {}
	local function select(index)
		for i, b in buttons do
			Kit.setStyle(b, i == index and "picked" or "plain")
		end
		onPick(index)
	end
	for i, name in names do
		local b = Kit.button(row, name, "plain", UDim2.new(1 / #names, -6 + 6 / #names, 1, 0))
		b.LayoutOrder = i
		b.TextSize = T.Small + 1
		b.Activated:Connect(function()
			select(i)
		end)
		buttons[i] = b
	end
	return row, select, buttons
end

-- "$1,234" with thousands commas.
function Kit.money(n)
	n = math.floor(tonumber(n) or 0)
	local s = tostring(math.abs(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return (n < 0 and "-$" or "$") .. out
end

return Kit
