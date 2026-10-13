--!nonstrict
-- The truck dealer's panel and the drive-out cutscene. Stand on the rug at Hank's counter and the panel opens with
-- every truck; the server decides every purchase. After buying, the camera stands outside the garage, watches the
-- roller door go up and follows your truck out onto the lot, then hands the camera back.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local Trucks = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Trucks"))
local remotes = ReplicatedStorage:WaitForChild("DealerRemotes")
local buyRemote = remotes:WaitForChild("Buy")
local cutsceneRemote = remotes:WaitForChild("Cutscene")
local studioCashRemote = remotes:WaitForChild("StudioCash")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local INK = Color3.fromRGB(40, 34, 28)
local PANEL = Color3.fromRGB(199, 186, 153) -- Rustic cream
local CARD = Color3.fromRGB(222, 212, 184)
local RED = Color3.fromRGB(133, 61, 48)
local GREEN = Color3.fromRGB(87, 107, 71)
local MUTED = Color3.fromRGB(150, 140, 120)

local gui = Instance.new("ScreenGui")
gui.Name = "DealerGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = playerGui

-- Panel ----------------------------------------------------------------------------------------------------------

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(1, 0.5)
panel.Position = UDim2.new(1, -16, 0.5, 0)
panel.Size = UDim2.fromOffset(340, 420)
panel.BackgroundColor3 = PANEL
panel.Visible = false
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)
local stroke = Instance.new("UIStroke", panel)
stroke.Color = INK
stroke.Thickness = 2

local function text(parent, value, size, y, height, color, font)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(14, y)
	label.Size = UDim2.new(1, -28, 0, height)
	label.Font = font or Enum.Font.GothamBold
	label.TextSize = size
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = color or INK
	label.Text = value
	label.Parent = parent
	return label
end

text(panel, "HOMESTEAD MOTORS", 22, 10, 28)
local cashLabel = text(panel, "", 16, 38, 20, GREEN)
local messageLabel = text(panel, "", 14, 386, 28, RED, Enum.Font.Gotham)

local list = Instance.new("ScrollingFrame")
list.Position = UDim2.fromOffset(10, 64)
list.Size = UDim2.new(1, -20, 0, 318)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 6
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new()
list.Parent = panel
local layout = Instance.new("UIListLayout", list)
layout.Padding = UDim.new(0, 8)
layout.SortOrder = Enum.SortOrder.LayoutOrder

local buttons = {} -- truck id -> button
local busy = false

local function owns(id)
	local ownedList = player:GetAttribute("OwnedTrucks") or ""
	for owned in string.gmatch(ownedList, "[^,]+") do
		if owned == id then
			return true
		end
	end
	return false
end

local function refresh()
	local cash = player:GetAttribute("Cash") or 0
	cashLabel.Text = ("Your cash: $%d"):format(cash)
	for _, def in Trucks do
		local button = buttons[def.id]
		if not def.available then
			button.Text = "COMING SOON"
			button.BackgroundColor3 = MUTED
			button.AutoButtonColor = false
		elseif owns(def.id) then
			button.Text = "GET MY TRUCK"
			button.BackgroundColor3 = GREEN
			button.AutoButtonColor = true
		elseif cash >= def.price then
			button.Text = ("BUY  $%d"):format(def.price)
			button.BackgroundColor3 = GREEN
			button.AutoButtonColor = true
		else
			button.Text = ("NEED $%d MORE"):format(def.price - cash)
			button.BackgroundColor3 = MUTED
			button.AutoButtonColor = true
		end
	end
end

for i, def in Trucks do
	local card = Instance.new("Frame")
	card.LayoutOrder = i
	card.Size = UDim2.new(1, -8, 0, 92)
	card.BackgroundColor3 = CARD
	card.Parent = list
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)
	text(card, def.name, 18, 6, 22)
	text(card, def.blurb, 13, 28, 32, INK, Enum.Font.Gotham)
	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(1, 1)
	button.Position = UDim2.new(1, -8, 1, -8)
	button.Size = UDim2.fromOffset(150, 28)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 14
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Parent = card
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 6)
	buttons[def.id] = button
	button.Activated:Connect(function()
		if busy or not def.available then
			return
		end
		busy = true
		messageLabel.Text = "..."
		local ok, okBuy, message = pcall(function()
			return buyRemote:InvokeServer(def.id)
		end)
		busy = false
		if not ok then
			messageLabel.Text = "Could not reach the counter. Try again."
			return
		end
		messageLabel.TextColor3 = okBuy and GREEN or RED
		messageLabel.Text = message or ""
		refresh()
	end)
end

-- Studio only: a button that adds test cash so the purchase can be tried without grinding.
if RunService:IsStudio() then
	local test = Instance.new("TextButton")
	test.Position = UDim2.new(1, -120, 0, 38)
	test.Size = UDim2.fromOffset(106, 20)
	test.Font = Enum.Font.Gotham
	test.TextSize = 12
	test.Text = "Studio: +$6,000"
	test.TextColor3 = INK
	test.BackgroundColor3 = CARD
	test.Parent = panel
	Instance.new("UICorner", test).CornerRadius = UDim.new(0, 6)
	test.Activated:Connect(function()
		studioCashRemote:FireServer()
	end)
end

player:GetAttributeChangedSignal("Cash"):Connect(refresh)
player:GetAttributeChangedSignal("OwnedTrucks"):Connect(refresh)
refresh()

-- The panel shows while you stand at the counter (on Hank's rug).
local inCutscene = false
task.spawn(function()
	while true do
		task.wait(0.2)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local near = false
		if root and not inCutscene then
			for _, rug in CollectionService:GetTagged("DealerCounter") do
				local offset = rug.CFrame:PointToObjectSpace(root.Position)
				if math.abs(offset.X) < rug.Size.X / 2 + 2 and math.abs(offset.Z) < rug.Size.Z / 2 + 2 and offset.Y < 8 then
					near = true
				end
			end
		end
		if near and not panel.Visible then
			messageLabel.Text = ""
			refresh()
		end
		panel.Visible = near
	end
end)

-- Cutscene -------------------------------------------------------------------------------------------------------

local bars = {}
for _, top in { true, false } do
	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0, top and 0 or 1)
	bar.Position = UDim2.fromScale(0, top and 0 or 1)
	bar.Size = UDim2.fromScale(1, 0)
	bar.BackgroundColor3 = Color3.new(0, 0, 0)
	bar.BorderSizePixel = 0
	bar.Parent = gui
	table.insert(bars, bar)
end

local title = Instance.new("TextLabel")
title.AnchorPoint = Vector2.new(0.5, 1)
title.Position = UDim2.new(0.5, 0, 1, -24)
title.Size = UDim2.fromOffset(600, 40)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 30
title.TextColor3 = Color3.fromRGB(235, 225, 200)
title.TextTransparency = 1
title.Parent = gui

local function letterbox(show)
	local info = TweenInfo.new(0.4)
	for _, bar in bars do
		TweenService:Create(bar, info, { Size = UDim2.fromScale(1, show and 0.12 or 0) }):Play()
	end
end

cutsceneRemote.OnClientEvent:Connect(function(data)
	local camera = workspace.CurrentCamera
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		return
	end
	inCutscene = true
	panel.Visible = false

	-- No jumping out of the seat mid-scene.
	pcall(function()
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	end)

	letterbox(true)
	title.Text = "YOUR " .. data.title
	TweenService:Create(title, TweenInfo.new(0.6), { TextTransparency = 0 }):Play()

	local previousType = camera.CameraType
	camera.CameraType = Enum.CameraType.Scriptable
	local from = data.camera
	local total = data.doorSeconds + data.driveSeconds + 0.6
	local started = os.clock()

	-- Watch the door open, then turn to follow the truck (you, in the driver's seat) out to the lot.
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - started
		local subject = root.Parent and root.Position or data.stop
		local focus
		if elapsed < data.doorSeconds then
			focus = data.door
		else
			local t = math.clamp((elapsed - data.doorSeconds) / 0.8, 0, 1)
			focus = data.door:Lerp(subject, t * t * (3 - 2 * t))
		end
		local drift = math.clamp(elapsed / total, 0, 1)
		local eye = from:Lerp(from + (data.stop - from) * 0.25 + Vector3.new(0, 2, 0), drift)
		camera.CFrame = CFrame.lookAt(eye, focus + Vector3.new(0, 1.5, 0))
	end)

	task.wait(total)
	connection:Disconnect()
	camera.CameraType = previousType == Enum.CameraType.Scriptable and Enum.CameraType.Custom or previousType
	camera.CameraSubject = humanoid
	letterbox(false)
	TweenService:Create(title, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
	pcall(function()
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	end)
	inCutscene = false
end)
