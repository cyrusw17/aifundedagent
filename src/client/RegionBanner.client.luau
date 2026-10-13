--!nonstrict
-- Shows the name of the region you've just entered ("PINE FOREST") across the top of the screen for a few seconds.
-- Regions are the ovals in Config/WorldMap.luau; Meadow is its square. Purely a label: nothing here decides anything.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Map = require(Shared.Config.WorldMap)
local Meadow = require(Shared.Config.Meadow)

local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "RegionBanner"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local label = Instance.new("TextLabel")
label.AnchorPoint = Vector2.new(0.5, 0)
label.Position = UDim2.new(0.5, 0, 0, 70)
label.Size = UDim2.fromOffset(520, 46)
label.BackgroundTransparency = 1
label.Font = Enum.Font.GothamBlack
label.TextSize = 38
label.TextColor3 = Color3.fromRGB(240, 228, 196)
label.TextStrokeColor3 = Color3.fromRGB(40, 34, 28)
label.TextTransparency = 1
label.TextStrokeTransparency = 1
label.Parent = gui

local function regionAt(position)
	if position.Y > Map.SkyIsland.top - 60 then
		local d = Vector2.new(position.X, position.Z) - Map.SkyIsland.center
		if d.Magnitude < Map.SkyIsland.radius + 40 then
			return "Sky Island"
		end
	end
	local cave = Map.Cave.chamber
	if (position - cave.center).Magnitude < cave.radius * 1.2 then
		return "Crystal Cave"
	end
	if math.abs(position.X) < Meadow.HalfSize and math.abs(position.Z) < Meadow.HalfSize then
		return "Meadow Farm"
	end
	local best, bestValue = nil, 0
	for _, r in Map.Regions do
		local dx = (position.X - r.center.X) / r.radius.X
		local dz = (position.Z - r.center.Y) / r.radius.Y
		local value = 1 - math.sqrt(dx * dx + dz * dz)
		if value > bestValue then
			best, bestValue = r.name, value
		end
	end
	return best
end

local shown = nil
local fadeIn = TweenInfo.new(0.6)
local fadeOut = TweenInfo.new(1.2)

local function show(name)
	label.Text = string.upper(name)
	TweenService:Create(label, fadeIn, { TextTransparency = 0, TextStrokeTransparency = 0.2 }):Play()
	task.delay(3.5, function()
		if label.Text == string.upper(name) then
			TweenService:Create(label, fadeOut, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
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
