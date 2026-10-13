--!nonstrict
-- Hold to keep scooping (the "Hold click to keep scooping" setting, on by default): while the click (or a gamepad's
-- right trigger) stays down with the shovel or rake out, the tool swings again each time its cooldown is up, so a
-- spill can be cleared without clicking every swing. The server still runs every swing and its cooldown
-- (Avatar.swing); this only clicks for you. Touch is left alone, since a held finger also turns the camera.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Game"))

local player = Players.LocalPlayer

local HOLD_INPUTS = {
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.KeyCode.ButtonR2] = true,
}
local held = nil -- the input being held, while it is
local nextSwing = 0

local function heldTool()
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	if tool and (tool.Name == "Shovel" or tool.Name == "Rake") then
		return tool
	end
	return nil
end

local function cooldown(tool)
	-- A hair over the server's cooldown, so each repeat lands on a ready tool instead of being dropped.
	return (tool.Name == "Rake" and Config.RakeCooldownSeconds or Config.ScoopCooldownSeconds) + 0.05
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	local key = HOLD_INPUTS[input.UserInputType] and input.UserInputType or HOLD_INPUTS[input.KeyCode] and input.KeyCode
	local tool = key and heldTool()
	if tool then
		held = key
		nextSwing = os.clock() + cooldown(tool) -- the click itself is the first swing
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == held or input.KeyCode == held then
		held = nil
	end
end)

RunService.Heartbeat:Connect(function()
	if not held or os.clock() < nextSwing then
		return
	end
	local tool = heldTool()
	if not tool or player:GetAttribute("SettingHoldScoop") == false then
		held = nil
		return
	end
	nextSwing = os.clock() + cooldown(tool)
	tool:Activate() -- the same as a click: the aim is sent (Main.client) and the server swings
end)
