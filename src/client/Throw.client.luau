--!nonstrict
-- Setting down and throwing a carried bale. A quick click (or G, or a tap) sets it down in front of you. Hold the
-- click or G to charge a throw: a bar fills, and letting go lobs the bale up to Config.TossRange studs, so loading
-- a pickup bed is a few quick throws. On a phone, the THROW button does the same: hold it, then let go. The server
-- does the throwing; this only reports how long the charge was held.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Game"))
local Kit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UI"):WaitForChild("Kit"))
local C, F = Kit.Theme.Colors, Kit.Theme.Fonts

local player = Players.LocalPlayer
local dropRemote = ReplicatedStorage:WaitForChild("DropBale")

local gui = Kit.screen("NeedlewoodThrow", 5)

-- The charge bar, just under the middle of the screen.
local bar = Instance.new("Frame")
bar.Name = "Charge"
bar.AnchorPoint = Vector2.new(0.5, 0)
bar.Position = UDim2.new(0.5, 0, 0.62, 0)
bar.Size = UDim2.fromOffset(160, 14)
bar.BackgroundColor3 = C.Wood
bar.Visible = false
bar.Parent = gui
Kit.corner(bar, 7)
Kit.stroke(bar, C.Ink, 1.5)
local fill = Instance.new("Frame")
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = C.Hay
fill.BorderSizePixel = 0
fill.Parent = bar
Kit.corner(fill, 7)
local caption = Instance.new("TextLabel")
caption.AnchorPoint = Vector2.new(0.5, 1)
caption.Position = UDim2.new(0.5, 0, 0, -2)
caption.Size = UDim2.fromOffset(160, 18)
caption.BackgroundTransparency = 1
caption.Font = F.Bold
caption.TextSize = 14
caption.TextColor3 = C.Cream
caption.TextStrokeTransparency = 0.5
caption.Text = "Throw"
caption.Parent = bar

-- The phone button: only on touch screens, only while carrying.
local throwButton = Instance.new("TextButton")
throwButton.Name = "Throw"
throwButton.AnchorPoint = Vector2.new(1, 1)
throwButton.Position = UDim2.new(1, -24, 1, -170)
throwButton.Size = UDim2.fromOffset(84, 84)
throwButton.BackgroundColor3 = C.Wood
throwButton.TextColor3 = C.Cream
throwButton.Font = F.Title
throwButton.TextSize = 16
throwButton.Text = "THROW"
throwButton.AutoButtonColor = true
throwButton.Visible = false
throwButton.Parent = gui
Kit.corner(throwButton, 42)
Kit.stroke(throwButton, C.Ink, 2)

local chargeStart = nil -- os.clock() when the current hold began
local chargeInput = nil -- what is being held: a KeyCode, a UserInputType, or "button"

local function power()
	if not chargeStart then
		return 0
	end
	return math.clamp((os.clock() - chargeStart) / Config.TossChargeSeconds, 0, 1)
end

local function begin(what)
	if chargeStart or not player:GetAttribute("Carrying") then
		return
	end
	chargeStart = os.clock()
	chargeInput = what
end

local function release(what)
	if not chargeStart or chargeInput ~= what then
		return
	end
	local p = power()
	chargeStart, chargeInput = nil, nil
	bar.Visible = false
	if not player:GetAttribute("Carrying") then
		return
	end
	if p < Config.TossMinPower then
		dropRemote:FireServer() -- a quick click: set it down
	else
		dropRemote:FireServer(p)
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		begin(Enum.UserInputType.MouseButton1)
	elseif input.KeyCode == Enum.KeyCode.G then
		begin(Enum.KeyCode.G)
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		release(Enum.UserInputType.MouseButton1)
	elseif input.KeyCode == Enum.KeyCode.G then
		release(Enum.KeyCode.G)
	end
end)
-- A tap on the world still sets the bale down. Touch is otherwise left alone: dragging the camera is a touch too.
UserInputService.TouchTap:Connect(function(_, gameProcessed)
	if not gameProcessed and not chargeStart and player:GetAttribute("Carrying") then
		dropRemote:FireServer()
	end
end)
throwButton.MouseButton1Down:Connect(function()
	begin("button")
end)
throwButton.MouseButton1Up:Connect(function()
	release("button")
end)
-- A finger that slides off the button before lifting still throws.
throwButton.MouseLeave:Connect(function()
	release("button")
end)

RunService.RenderStepped:Connect(function()
	if not chargeStart then
		return
	end
	if not player:GetAttribute("Carrying") then
		chargeStart, chargeInput = nil, nil
		bar.Visible = false
		return
	end
	local p = power()
	-- The bar only shows once the hold is clearly a throw, so a plain click to set down shows nothing.
	bar.Visible = p >= Config.TossMinPower
	fill.Size = UDim2.fromScale(p, 1)
	caption.Text = p >= 1 and "Throw (full)" or "Throw"
end)

local function refreshButton()
	throwButton.Visible = UserInputService.TouchEnabled and player:GetAttribute("Carrying") == true
end
player:GetAttributeChangedSignal("Carrying"):Connect(refreshButton)
refreshButton()
