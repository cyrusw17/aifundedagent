--!nonstrict
-- Shows the name of the region you've just entered ("PINE FOREST") across the top of the screen for a few seconds.
-- Which region: Shared/WorldRegions.luau. Purely a label: nothing here decides anything.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldRegions = require(Shared.WorldRegions)
local Hud = require(Shared:WaitForChild("UI"):WaitForChild("Hud"))

local player = Players.LocalPlayer

local label = Instance.new("TextLabel")
label.AnchorPoint = Vector2.new(0.5, 0)
label.LayoutOrder = Hud.TopOrder.RegionBanner -- in the top-center stack (UI/Hud.luau)
label.Size = UDim2.fromOffset(520, 46)
label.Visible = false
label.BackgroundTransparency = 1
label.Font = Enum.Font.GothamBlack
label.TextSize = 38
label.TextColor3 = Color3.fromRGB(240, 228, 196)
label.TextStrokeColor3 = Color3.fromRGB(40, 34, 28)
label.TextTransparency = 1
label.TextStrokeTransparency = 1
label.Parent = Hud.top()

local function regionAt(position)
	local region = WorldRegions.at(position)
	return region and region.name
end

local shown = nil
local fadeIn = TweenInfo.new(0.6)
local fadeOut = TweenInfo.new(1.2)

local function show(name)
	label.Text = string.upper(name)
	label.Visible = true
	TweenService:Create(label, fadeIn, { TextTransparency = 0, TextStrokeTransparency = 0.2 }):Play()
	task.delay(3.5, function()
		if label.Text == string.upper(name) then
			local out = TweenService:Create(label, fadeOut, { TextTransparency = 1, TextStrokeTransparency = 1 })
			out:Play()
			out.Completed:Once(function()
				-- Hidden, it gives its room in the top stack back.
				if label.TextTransparency >= 1 then
					label.Visible = false
				end
			end)
		end
	end)
end

while true do
	task.wait(1)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		local name = regionAt(root.Position)
		if name and name ~= shown then
			-- Skip the banner for the place you spawn in.
			if shown ~= nil then
				show(name)
			end
			shown = name
		end
	end
end
