--!nonstrict
-- The "working together" chip (CEO H12): while a friend helps on your farm, Land.luau sets your TogetherBonus
-- attribute to their DisplayName and your needles get Config/Land TogetherBonus (+10%); it is nil when the bonus is
-- off. This only shows it, as a small green pill under the countdown strip in the top-center stack (UI/Hud.luau).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UI")
local Kit = require(UI:WaitForChild("Kit"))
local Hud = require(UI:WaitForChild("Hud"))
local LandConfig = require(ReplicatedStorage.Shared:WaitForChild("Config"):WaitForChild("Land"))
local C, F = Kit.Theme.Colors, Kit.Theme.Fonts

local player = Players.LocalPlayer

local chip = Instance.new("Frame")
chip.Name = "Together"
chip.LayoutOrder = Hud.TopOrder.Together
chip.Size = UDim2.fromOffset(0, 24)
chip.AutomaticSize = Enum.AutomaticSize.X
chip.BackgroundColor3 = C.Green
chip.BackgroundTransparency = 0.1
chip.Visible = false
chip.Parent = Hud.top()
Kit.corner(chip, 12)
Kit.stroke(chip, C.Ink, 1.5)
local pad = Instance.new("UIPadding")
pad.PaddingLeft = UDim.new(0, 12)
pad.PaddingRight = UDim.new(0, 12)
pad.Parent = chip
local limit = Instance.new("UISizeConstraint")
limit.MaxSize = Vector2.new(440, 24)
limit.Parent = chip
local text = Kit.label(chip, "", { size = 14, font = F.Bold, color = C.Cream, wrap = false })
text.Size = UDim2.fromScale(0, 1)
text.AutomaticSize = Enum.AutomaticSize.X
text.TextTruncate = Enum.TextTruncate.AtEnd

local function refresh()
	local helper = player:GetAttribute("TogetherBonus")
	local on = typeof(helper) == "string" and helper ~= ""
	chip.Visible = on
	if on then
		local percent = math.floor((((LandConfig :: any).TogetherBonus or 1.1) - 1) * 100 + 0.5)
		text.Text = ("+%d%% needles: %s is helping"):format(percent, helper)
	end
end
player:GetAttributeChangedSignal("TogetherBonus"):Connect(refresh)
refresh()
