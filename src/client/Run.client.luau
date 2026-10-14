--!nonstrict
-- Running (Cyrus, 2026-10-14). Hold Shift, or click a gamepad's left stick to toggle, and you move
-- Config.RunMultiplier times faster than the load lets you walk. On touch screens a RUN button by the jump button
-- toggles it. The server sets the speed (Avatar.setRunning via the SetRun remote); this only says when.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("SetRun", 30)
if not remote then
	warn("[Needlewood] no SetRun remote, so running is off")
	return
end

local shiftHeld = false
local toggled = false -- the gamepad stick click or the touch button
local sent = false

local button

local function update()
	local want = shiftHeld or toggled
	if want ~= sent then
		sent = want
		remote:FireServer(want)
	end
	if button then
		button.BackgroundTransparency = want and 0.1 or 0.45
		button.Text = want and "RUNNING" or "RUN"
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		if not UserInputService:GetFocusedTextBox() then
			shiftHeld = true
			update()
		end
	elseif input.KeyCode == Enum.KeyCode.ButtonL3 and not gameProcessed then
		toggled = not toggled
		update()
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		shiftHeld = false
		update()
	end
end)

-- The touch button, above and left of Roblox's jump button.
if UserInputService.TouchEnabled then
	local gui = Instance.new("ScreenGui")
	gui.Name = "RunButton"
	gui.ResetOnSpawn = false
	button = Instance.new("TextButton")
	button.Name = "Run"
	button.AnchorPoint = Vector2.new(1, 1)
	button.Position = UDim2.new(1, -110, 1, -150)
	button.Size = UDim2.fromOffset(72, 40)
	button.BackgroundColor3 = Color3.fromRGB(92, 74, 54)
	button.TextColor3 = Color3.fromRGB(240, 230, 210)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 16
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = button
	button.Activated:Connect(function()
		toggled = not toggled
		update()
	end)
	button.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
	update()
end

-- A new character starts walking, so a stale toggle never leaves you running after a respawn without the button
-- saying so.
player.CharacterAdded:Connect(function()
	toggled = false
	shiftHeld = false
	sent = true -- forces the server to hear "off"
	update()
end)
