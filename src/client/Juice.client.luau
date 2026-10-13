--!nonstrict
-- Game feel on your own screen, fired by the server (Feedback.juice): a smashed bale freezes your swing for a
-- 40 ms hit-stop and jolts the camera, a scoop combo gives a tiny shake that grows with the combo, and a rare needle
-- coming out of the hay ("reveal", Shared/Reveal) tips the camera up a touch and lets it settle. Only the
-- camera and your own animations move; nothing here changes the game.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("Juice")

local HIT_STOP = 0.04
local shake = 0 -- current shake strength in studs, fading out
local kick = 0 -- current reveal nudge in studs, easing back
local FADE = 9 -- per second
local rng = Random.new()

local function hitStop()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local frozen = {}
	for _, track in animator:GetPlayingAnimationTracks() do
		frozen[track] = track.Speed
		track:AdjustSpeed(0)
	end
	task.delay(HIT_STOP, function()
		for track, speed in frozen do
			track:AdjustSpeed(speed)
		end
	end)
end

remote.OnClientEvent:Connect(function(kind, amount)
	if kind == "burst" then
		hitStop()
		shake = math.max(shake, 0.35)
	elseif kind == "reveal" then
		kick = math.max(kick, math.clamp(tonumber(amount) or 0, 0, 0.35))
	elseif kind == "combo" then
		shake = math.max(shake, math.min(0.08 + 0.05 * (tonumber(amount) or 1), 0.3))
	end
end)

-- After the camera has moved this frame, nudge it by the shake.
RunService:BindToRenderStep("NeedlewoodJuice", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if kick > 0.001 then
		local camera = workspace.CurrentCamera
		if camera then
			camera.CFrame *= CFrame.new(0, kick, 0) * CFrame.Angles(math.rad(kick * 8), 0, 0)
		end
		kick = math.max(0, kick - 3 * kick * dt - 0.05 * dt)
	else
		kick = 0
	end
	if shake <= 0.001 then
		shake = 0
		return
	end
	local camera = workspace.CurrentCamera
	if camera then
		camera.CFrame *= CFrame.new(rng:NextNumber(-shake, shake), rng:NextNumber(-shake, shake), 0)
	end
	shake = math.max(0, shake - FADE * shake * dt - 0.2 * dt)
end)
