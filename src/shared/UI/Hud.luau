--!nonstrict
-- The left HUD column: one stack at the top-left that the HUD card, the bank line, the goal bar and the menu
-- buttons all sit in, so they never overlap and scale together (Settings UI size, and smaller on phones).
-- Client only.
--   local column = Hud.column()      -- a Frame with a vertical list layout
--   card.LayoutOrder = Hud.Order.Cash; card.Parent = column
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Kit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UI"):WaitForChild("Kit"))

local Hud = {}

-- Where each piece sits in the column, top to bottom.
Hud.Order = { Cash = 10, Bank = 20, Goal = 30, Buttons = 40, Extra = 50 }

-- The top-center stack, top to bottom (Hud.top()). Hidden pieces take no room, so nothing up there overlaps.
Hud.TopOrder = {
	Compass = 10,
	Region = 20,
	Countdown = 25,
	Together = 27,
	Announce = 30,
	RegionBanner = 40,
	Toast = 50,
	Guide = 60,
}

local column = nil
local scale = nil

local function update()
	if not scale then
		return
	end
	-- The UI size setting, times a phone factor on short screens.
	local camera = Workspace.CurrentCamera
	local view = camera and camera.ViewportSize or Vector2.new(1024, 768)
	local phone = view.Y < 520 and 0.78 or 1
	scale.Scale = Kit.userScale() * phone
end

function Hud.column()
	if column then
		return column
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "NeedlewoodColumn"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 4
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	column = Instance.new("Frame")
	column.Name = "Column"
	column.Position = UDim2.fromOffset(14, 14)
	column.Size = UDim2.fromOffset(230, 0)
	column.AutomaticSize = Enum.AutomaticSize.Y
	column.BackgroundTransparency = 1
	column.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = column
	scale = Instance.new("UIScale")
	scale.Parent = column

	update()
	Players.LocalPlayer:GetAttributeChangedSignal("SettingUiSize"):Connect(update)
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	end
	return column
end

-- The top-center stack: the compass, server banners, the region title, toasts and the guide card stack down from
-- the top edge in Hud.TopOrder, so they never cover each other. A piece's Position is ignored inside it; hide a
-- piece (Visible = false) when it has nothing to show so it gives its room back.
local top = nil
local topScale = nil
local function updateTop()
	if not topScale then
		return
	end
	local camera = Workspace.CurrentCamera
	local view = camera and camera.ViewportSize or Vector2.new(1024, 768)
	topScale.Scale = Kit.userScale() * (view.Y < 520 and 0.78 or 1)
end
function Hud.top()
	if top then
		return top
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "NeedlewoodTop"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 6
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	top = Instance.new("Frame")
	top.Name = "Top"
	top.AnchorPoint = Vector2.new(0.5, 0)
	top.Position = UDim2.new(0.5, 0, 0, 4)
	top.Size = UDim2.fromOffset(560, 0)
	top.AutomaticSize = Enum.AutomaticSize.Y
	top.BackgroundTransparency = 1
	top.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = top
	topScale = Instance.new("UIScale")
	topScale.Parent = top

	updateTop()
	Players.LocalPlayer:GetAttributeChangedSignal("SettingUiSize"):Connect(updateTop)
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateTop)
	end
	return top
end

-- True on a phone or tablet with no keyboard.
function Hud.touchOnly()
	local UserInputService = game:GetService("UserInputService")
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

return Hud
