--!nonstrict
-- One waypoint at a time: a glowing line from you to the spot and a pin above it with its name and distance.
-- Used by the map, the shop's "Show me" buttons and the guide. Client only.
--   Waypoint.set(position, "Land Office")   Waypoint.clear()
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Theme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UI"):WaitForChild("Theme"))

local Waypoint = {}
Waypoint.changed = Instance.new("BindableEvent") -- (position or nil, name)

local player = Players.LocalPlayer
local ARRIVE = 14 -- studs: close enough, the waypoint clears itself unless it is sticky

local anchor = Instance.new("Part")
anchor.Name = "WaypointAnchor"
anchor.Anchored = true
anchor.CanCollide = false
anchor.CanQuery = false
anchor.CanTouch = false
anchor.Transparency = 1
anchor.Size = Vector3.new(1, 1, 1)
local targetAttachment = Instance.new("Attachment")
targetAttachment.Position = Vector3.new(0, 1.5, 0)
targetAttachment.Parent = anchor

local beam = Instance.new("Beam")
beam.Attachment1 = targetAttachment
beam.Color = ColorSequence.new(Theme.Colors.Hay)
beam.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.6),
	NumberSequenceKeypoint.new(0.15, 0.25),
	NumberSequenceKeypoint.new(1, 0.25),
})
beam.LightEmission = 0.6
beam.LightInfluence = 0
beam.FaceCamera = true
beam.Width0 = 0.35
beam.Width1 = 0.35
beam.Segments = 1
beam.Parent = anchor

local pin = Instance.new("BillboardGui")
pin.Size = UDim2.fromOffset(180, 46)
pin.StudsOffset = Vector3.new(0, 7, 0)
pin.AlwaysOnTop = true
pin.LightInfluence = 0
pin.MaxDistance = 100000
pin.Parent = anchor
local pinText = Instance.new("TextLabel")
pinText.Size = UDim2.fromScale(1, 1)
pinText.BackgroundTransparency = 1
pinText.Font = Theme.Fonts.Bold
pinText.TextSize = 14
pinText.TextColor3 = Theme.Colors.Cream
pinText.TextStrokeColor3 = Theme.Colors.Ink
pinText.TextStrokeTransparency = 0.1
pinText.Parent = pin

local rootAttachment = nil
local name = ""
local sticky = false
local connection = nil

local function attachToCharacter()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		beam.Attachment0 = nil
		return
	end
	if not rootAttachment or rootAttachment.Parent ~= root then
		rootAttachment = Instance.new("Attachment")
		rootAttachment.Name = "WaypointFrom"
		rootAttachment.Position = Vector3.new(0, -1.5, 0)
		rootAttachment.Parent = root
	end
	beam.Attachment0 = rootAttachment
end

-- position: Vector3 on the ground. label: shown on the pin. keep: don't clear on arrival (the guide moves it).
function Waypoint.set(position, label, keep)
	if not position then
		Waypoint.clear()
		return
	end
	name = label or ""
	sticky = keep == true
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = Workspace
	attachToCharacter()
	if not connection then
		connection = RunService.Heartbeat:Connect(function()
			attachToCharacter()
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if not root then
				return
			end
			local flat = Vector3.new(anchor.Position.X - root.Position.X, 0, anchor.Position.Z - root.Position.Z)
			local distance = flat.Magnitude
			pinText.Text = ("▼ %s  ·  %d"):format(name, math.floor(distance))
			beam.Enabled = distance > 6
			if distance < ARRIVE and not sticky then
				Waypoint.clear()
			end
		end)
	end
	Waypoint.changed:Fire(position, name)
end

function Waypoint.clear()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	anchor.Parent = nil
	Waypoint.changed:Fire(nil, nil)
end

function Waypoint.position()
	return anchor.Parent and anchor.Position or nil
end

player.CharacterAdded:Connect(function()
	task.defer(attachToCharacter)
end)

return Waypoint
