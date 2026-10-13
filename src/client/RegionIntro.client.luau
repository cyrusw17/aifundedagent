--!nonstrict
-- First visit to a region (map #24): a 3-second camera sweep over its landmark with the region's name, once per save
-- (the server only sends it the first time Discoveries stamps the region). Skipped while you drive, or when another
-- camera (build mode, a cutscene) already has the camera; the banner still shows (RegionBanner.client.luau).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("RegionIntro", 60)
if not remote then
	return
end

local PAN = 3 -- seconds over the landmark
local BACK = 0.6 -- seconds to swing back to the player
local RADIUS = 90 -- studs out from the landmark
local HEIGHT = 45 -- studs above it
local SWEEP = math.rad(50) -- how far round the landmark the camera travels

local gui = Instance.new("ScreenGui")
gui.Name = "RegionIntro"
gui.ResetOnSpawn = false
gui.DisplayOrder = 5
gui.Parent = player:WaitForChild("PlayerGui")

local function bar(y)
	local f = Instance.new("Frame")
	f.BackgroundColor3 = Color3.new(0, 0, 0)
	f.BorderSizePixel = 0
	f.AnchorPoint = Vector2.new(0, y)
	f.Position = UDim2.fromScale(0, y)
	f.Size = UDim2.new(1, 0, 0, 0)
	f.Parent = gui
	return f
end
local top, bottom = bar(0), bar(1)

local title = Instance.new("TextLabel")
title.AnchorPoint = Vector2.new(0.5, 1)
title.Position = UDim2.new(0.5, 0, 1, -70)
title.Size = UDim2.fromOffset(700, 60)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBlack
title.TextSize = 46
title.TextColor3 = Color3.fromRGB(240, 228, 196)
title.TextStrokeColor3 = Color3.fromRGB(40, 34, 28)
title.TextTransparency = 1
title.TextStrokeTransparency = 1
title.Parent = gui

local sub = title:Clone()
sub.Position = UDim2.new(0.5, 0, 1, -40)
sub.Size = UDim2.fromOffset(700, 26)
sub.TextSize = 20
sub.Font = Enum.Font.GothamBold
sub.Text = "NEW REGION"
sub.Parent = gui

local playing = false

local function letterbox(on)
	local size = on and UDim2.new(1, 0, 0.11, 0) or UDim2.new(1, 0, 0, 0)
	local info = TweenInfo.new(0.4)
	TweenService:Create(top, info, { Size = size }):Play()
	TweenService:Create(bottom, info, { Size = size }):Play()
	local text = on and 0 or 1
	for _, label in { title, sub } do
		TweenService:Create(label, info, { TextTransparency = text, TextStrokeTransparency = on and 0.2 or 1 }):Play()
	end
end

local function canPan()
	local camera = workspace.CurrentCamera
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not camera or camera.CameraType ~= Enum.CameraType.Custom then
		return false
	end
	-- Never take the camera from a driver.
	return not (humanoid and humanoid.SeatPart and humanoid.SeatPart:IsA("VehicleSeat"))
end

remote.OnClientEvent:Connect(function(name, focus)
	if playing or typeof(focus) ~= "Vector3" or type(name) ~= "string" or not canPan() then
		return
	end
	playing = true
	local camera = workspace.CurrentCamera
	local before = camera.CFrame
	title.Text = string.upper(name)
	camera.CameraType = Enum.CameraType.Scriptable
	letterbox(true)
	-- Start on the side of the landmark facing the player, then sweep round it.
	local toPlayer = Vector3.new(before.Position.X - focus.X, 0, before.Position.Z - focus.Z)
	local start = toPlayer.Magnitude > 1 and math.atan2(toPlayer.Z, toPlayer.X) or 0
	local look = focus + Vector3.new(0, 10, 0)
	local t = 0
	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		t += dt
		local a = start + SWEEP * math.min(t / PAN, 1)
		local eye = focus + Vector3.new(math.cos(a) * RADIUS, HEIGHT, math.sin(a) * RADIUS)
		camera.CFrame = CFrame.lookAt(eye, look)
		if t >= PAN then
			connection:Disconnect()
		end
	end)
	task.wait(PAN)
	if connection.Connected then
		connection:Disconnect()
	end
	letterbox(false)
	-- Swing back to where the player's own camera would be, then hand it back.
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local home = before
	if root then
		home = CFrame.lookAt(root.Position - before.LookVector * (before.Position - root.Position).Magnitude, root.Position)
	end
	local back = TweenService:Create(camera, TweenInfo.new(BACK, Enum.EasingStyle.Sine), { CFrame = home })
	back:Play()
	back.Completed:Wait()
	camera.CameraType = Enum.CameraType.Custom
	playing = false
end)
