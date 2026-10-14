--!nonstrict
-- The compass strip at the top of the screen: which way the camera faces (N, NE, E...), the region you're in, and
-- pins for your truck, your plot, the quest you're tracking, the rich field and any region event. A pin past the
-- strip's edge sits at that edge, faded, so it still says which way to turn. North is -Z.
-- Reads only what is already published: the player's TruckSpots, ReplicatedStorage.Land Plot* OwnerId/Corner/Tiles,
-- the player's QuestTrackTarget, ReplicatedStorage RichField and RegionEventAt.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Kit = require(Shared:WaitForChild("UI"):WaitForChild("Kit"))
local Hud = require(Shared:WaitForChild("UI"):WaitForChild("Hud"))
local WorldRegions = require(Shared:WaitForChild("WorldRegions"))
local Factory = require(Shared:WaitForChild("Config"):WaitForChild("Factory"))
local C, F = Kit.Theme.Colors, Kit.Theme.Fonts

local player = Players.LocalPlayer

local WIDTH, HEIGHT = 440, 30
local SPAN = 160 -- degrees of heading across the strip
local TICKS = { [0] = "N", [45] = "NE", [90] = "E", [135] = "SE", [180] = "S", [225] = "SW", [270] = "W", [315] = "NW" }

local strip = Instance.new("Frame")
strip.Name = "Strip"
strip.AnchorPoint = Vector2.new(0.5, 0)
strip.LayoutOrder = Hud.TopOrder.Compass -- first in the top-center stack (UI/Hud.luau)
strip.Size = UDim2.fromOffset(WIDTH, HEIGHT)
strip.BackgroundColor3 = C.Wood
strip.BackgroundTransparency = 0.15
strip.ClipsDescendants = true
strip.Parent = Hud.top()
Kit.corner(strip, 8)
Kit.stroke(strip, C.Ink, 1.5)

local center = Instance.new("Frame")
center.Name = "Center"
center.AnchorPoint = Vector2.new(0.5, 0)
center.Position = UDim2.new(0.5, 0, 0, 0)
center.Size = UDim2.fromOffset(2, 6)
center.BackgroundColor3 = C.Hay
center.BorderSizePixel = 0
center.ZIndex = 3
center.Parent = strip

local regionLabel = Instance.new("TextLabel")
regionLabel.Name = "Region"
regionLabel.AnchorPoint = Vector2.new(0.5, 0)
regionLabel.LayoutOrder = Hud.TopOrder.Region
regionLabel.Size = UDim2.fromOffset(WIDTH, 16)
regionLabel.BackgroundTransparency = 1
regionLabel.Font = F.Bold
regionLabel.TextSize = 13
regionLabel.TextColor3 = C.Cream
regionLabel.TextStrokeTransparency = 0.4
regionLabel.Text = ""
regionLabel.Parent = Hud.top()

-- Heading marks every 15 degrees: letters at the eight points, small ticks between.
local marks = {}
for deg = 0, 345, 15 do
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.Font = TICKS[deg] and F.Title or F.Medium
	label.TextSize = TICKS[deg] and (#TICKS[deg] == 1 and 17 or 13) or 10
	label.TextColor3 = deg == 0 and C.Red or C.Cream
	label.Text = TICKS[deg] or "|"
	label.TextTransparency = TICKS[deg] and 0 or 0.5
	label.Size = UDim2.fromOffset(30, HEIGHT)
	label.Parent = strip
	marks[deg] = label
end

-- Pins: a colored dot with a letter.
local PINS = {
	truck = { letter = "T", color = C.Blue },
	plot = { letter = "H", color = C.Green },
	quest = { letter = "!", color = C.Picked },
	rich = { letter = "$", color = Color3.fromRGB(242, 183, 5) },
	event = { letter = "*", color = C.Red },
}
local pinLabels = {}
for id, def in PINS do
	local dot = Instance.new("TextLabel")
	dot.Name = "Pin_" .. id
	dot.AnchorPoint = Vector2.new(0.5, 1)
	dot.Size = UDim2.fromOffset(16, 16)
	dot.BackgroundColor3 = def.color
	dot.Font = F.Title
	dot.TextSize = 11
	dot.TextColor3 = C.Ink
	dot.Text = def.letter
	dot.ZIndex = 4
	dot.Visible = false
	dot.Parent = strip
	Kit.corner(dot, 8)
	pinLabels[id] = dot
end

local function bearing(dx, dz)
	return math.deg(math.atan2(dx, -dz)) % 360
end

-- Signed difference a - b in degrees, -180..180.
local function delta(a, b)
	return (a - b + 540) % 360 - 180
end

local targets = {} -- pin id -> Vector3 or nil

-- Your truck, from the server's "TruckSpots" player attribute ("x,z;x,z", TruckSpots.luau), so the pin stays even
-- when the truck is streamed out and no Workspace scan is needed. The first truck listed is the one pinned.
local function findTruck()
	local x, z = string.match(player:GetAttribute("TruckSpots") or "", "^(%-?[%d%.]+),(%-?[%d%.]+)")
	if not x then
		return nil
	end
	return Vector3.new(tonumber(x), 0, tonumber(z))
end

local function findPlot()
	local land = ReplicatedStorage:FindFirstChild("Land")
	if not land then
		return nil
	end
	for _, info in land:GetChildren() do
		if info:GetAttribute("OwnerId") == player.UserId and info:GetAttribute("Corner") then
			local corner = info:GetAttribute("Corner")
			local tx, tz = info:GetAttribute("TilesX") or 0, info:GetAttribute("TilesZ") or 0
			return corner + Vector3.new(tx * Factory.TileSize / 2, 0, tz * Factory.TileSize / 2)
		end
	end
	return nil
end

local sinceScan = 10
RunService.RenderStepped:Connect(function(dt)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local look = camera.CFrame.LookVector
	local heading = bearing(look.X, look.Z)
	local from = camera.CFrame.Position

	sinceScan += dt
	if sinceScan > 2 then
		sinceScan = 0
		targets.truck = findTruck()
		targets.plot = findPlot()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local region = WorldRegions.at(root and root.Position or from)
		regionLabel.Text = region and region.name or "Open sea"
	end
	local quest = player:GetAttribute("QuestTrackTarget")
	targets.quest = typeof(quest) == "Vector3" and quest or nil
	local rich = ReplicatedStorage:GetAttribute("RichField")
	targets.rich = typeof(rich) == "Vector3" and rich or nil
	local event = ReplicatedStorage:GetAttribute("RegionEventAt")
	targets.event = typeof(event) == "Vector3" and event or nil

	for deg, label in marks do
		local d = delta(deg, heading)
		label.Visible = math.abs(d) < SPAN / 2 + 8
		label.Position = UDim2.new(0.5 + d / SPAN, 0, 0.5, 0)
	end
	for id, dot in pinLabels do
		local at = targets[id]
		if at and (Vector2.new(at.X, at.Z) - Vector2.new(from.X, from.Z)).Magnitude > 12 then
			local d = delta(bearing(at.X - from.X, at.Z - from.Z), heading)
			local edge = math.abs(d) > SPAN / 2 - 4
			d = math.clamp(d, -SPAN / 2 + 4, SPAN / 2 - 4)
			dot.Position = UDim2.new(0.5 + d / SPAN, 0, 1, -2)
			dot.BackgroundTransparency = edge and 0.5 or 0
			dot.TextTransparency = edge and 0.4 or 0
			dot.Visible = true
		else
			dot.Visible = false
		end
	end
end)
