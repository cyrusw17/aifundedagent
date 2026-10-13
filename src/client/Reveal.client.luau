--!nonstrict
-- The clip-worthy needle reveal (Needle.luau clipMoment, Shared/Reveal): when you find an Epic or better needle, or
-- any mutation, the camera pushes in on it in slow motion for about 1.5 s while a rarity card names the needle and
-- you. Any key, click or tap skips it and gives the camera straight back. Legendary and mutated finds also put a
-- line in server chat. A player can turn the push-in off with the RevealCamera attribute set to false.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local TextChatService = game:GetService("TextChatService")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("NeedleReveal", 600)
if not remote then
	return
end

local NEAR = 90 -- studs: further than this, the find gets its card but the camera stays put
local DOLLY = 0.55 -- how far along the way to the needle the camera ends up (eased, so it feels like slow motion)

-- The card -------------------------------------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "NeedleReveal"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 20
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local card = Instance.new("Frame")
card.AnchorPoint = Vector2.new(0.5, 1)
card.Position = UDim2.new(0.5, 0, 0.82, 0)
card.Size = UDim2.fromOffset(440, 96)
card.BackgroundColor3 = Color3.fromRGB(34, 28, 22)
card.BackgroundTransparency = 0.15
card.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = card
local edge = Instance.new("UIStroke")
edge.Thickness = 3
edge.Parent = card
local limit = Instance.new("UISizeConstraint")
limit.MaxSize = Vector2.new(440, 96)
limit.Parent = card
card.Size = UDim2.new(0.9, 0, 0, 96)

local function label(y, h, size, font)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = UDim2.new(0, 12, 0, y)
	l.Size = UDim2.new(1, -24, 0, h)
	l.Font = font
	l.TextSize = size
	l.TextScaled = false
	l.TextWrapped = true
	l.TextColor3 = Color3.fromRGB(245, 236, 214)
	l.TextStrokeTransparency = 0.6
	l.Parent = card
	return l
end
local title = label(8, 34, 26, Enum.Font.GothamBlack)
local who = label(44, 22, 17, Enum.Font.GothamBold)
local skip = label(70, 18, 12, Enum.Font.Gotham)
skip.TextTransparency = 0.35
skip.Text = UserInputService.TouchEnabled and "Tap to skip" or "Press any key or click to skip"

-- The push-in ------------------------------------------------------------------------------------------------------
local playing = nil -- { stop = function } while a reveal runs

local function stopReveal()
	if playing then
		playing.stop()
	end
end

local function show(info)
	stopReveal()
	local camera = workspace.CurrentCamera
	local token = {}
	local done = false
	local tween
	local oldType = camera and camera.CameraType
	local function stop()
		if done then
			return
		end
		done = true
		if tween then
			tween:Cancel()
		end
		if camera and oldType and camera.CameraType == Enum.CameraType.Scriptable then
			camera.CameraType = oldType
		end
		gui.Enabled = false
		if playing == token then
			playing = nil
		end
	end
	token.stop = stop
	playing = token

	title.Text = tostring(info.title or "RARE NEEDLE")
	who.Text = ("%s found it! $%d"):format(tostring(info.finder or player.DisplayName), math.floor(tonumber(info.value) or 0))
	local color = typeof(info.color) == "Color3" and info.color or Color3.fromRGB(250, 214, 110)
	edge.Color = color
	title.TextColor3 = color
	gui.Enabled = true

	local seconds = math.clamp(tonumber(info.seconds) or 1.5, 0.5, 3)
	local at = typeof(info.part) == "Instance" and info.part:IsA("BasePart") and info.part.Position or info.at
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local cinematic = info.cinematic and player:GetAttribute("RevealCamera") ~= false and camera and typeof(at) == "Vector3"
		and root and (root.Position - at).Magnitude <= NEAR
	if cinematic then
		local from = camera.CFrame
		local target = at + Vector3.new(0, 0.6, 0)
		local stand = from.Position:Lerp(target, DOLLY)
		camera.CameraType = Enum.CameraType.Scriptable
		tween = TweenService:Create(camera, TweenInfo.new(seconds, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			CFrame = CFrame.lookAt(stand, target),
		})
		tween:Play()
	end
	task.delay(cinematic and seconds + 0.2 or 3, function()
		if playing == token then
			stop()
		end
	end)
end

-- Any key, click or tap skips (the camera comes straight back).
UserInputService.InputBegan:Connect(function(input)
	if not playing then
		return
	end
	local t = input.UserInputType
	if t == Enum.UserInputType.Keyboard or t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.MouseButton2
		or t == Enum.UserInputType.Touch or t == Enum.UserInputType.Gamepad1 then
		stopReveal()
	end
end)
-- Dying or respawning mid-reveal hands the camera back too.
player.CharacterAdded:Connect(stopReveal)
RunService.Stepped:Connect(function()
	if playing and not (player.Character and player.Character:FindFirstChildOfClass("Humanoid")) then
		stopReveal()
	end
end)

-- Server chat ------------------------------------------------------------------------------------------------------
local function chatLine(text)
	local ok = pcall(function()
		local channels = TextChatService:FindFirstChild("TextChannels")
		local general = channels and channels:FindFirstChild("RBXGeneral")
		if not general then
			error("no RBXGeneral")
		end
		general:DisplaySystemMessage(text)
	end)
	if not ok then
		pcall(function()
			StarterGui:SetCore("ChatMakeSystemMessage", { Text = text, Color = Color3.fromRGB(250, 214, 110) })
		end)
	end
end

remote.OnClientEvent:Connect(function(kind, payload)
	if kind == "clip" and typeof(payload) == "table" then
		show(payload)
	elseif kind == "chat" and typeof(payload) == "string" then
		chatLine(payload)
	end
end)
