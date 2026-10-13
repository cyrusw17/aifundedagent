--!nonstrict
-- Client entry point. Shows the HUD only. The client never decides what was found or earned.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "NeedlewoodHud"
gui.ResetOnSpawn = false
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(230, 112)
panel.Position = UDim2.fromOffset(14, 14)
panel.BackgroundColor3 = Color3.fromRGB(20, 34, 26)
panel.BackgroundTransparency = 0.25
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)

local function makeLabel(y, size)
	local label = Instance.new("TextLabel")
	label.Position = UDim2.fromOffset(12, y)
	label.Size = UDim2.new(1, -24, 0, size)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = size - 4
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Parent = panel
	return label
end

local cashLabel = makeLabel(8, 30)
cashLabel.TextColor3 = Color3.fromRGB(125, 255, 168)
local loadLabel = makeLabel(40, 22)

local barBack = Instance.new("Frame")
barBack.Position = UDim2.fromOffset(12, 68)
barBack.Size = UDim2.new(1, -24, 0, 10)
barBack.BackgroundColor3 = Color3.fromRGB(60, 78, 66)
barBack.Parent = panel
Instance.new("UICorner", barBack).CornerRadius = UDim.new(0, 5)

local bar = Instance.new("Frame")
bar.Size = UDim2.fromScale(0, 1)
bar.BackgroundColor3 = Color3.fromRGB(240, 173, 46)
bar.Parent = barBack
Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 5)

-- One line saying what a click does with what is in your hands right now.
local hintLabel = makeLabel(84, 20)
hintLabel.Font = Enum.Font.Gotham
hintLabel.TextColor3 = Color3.fromRGB(214, 226, 218)

local toast = Instance.new("TextLabel")
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.new(0.5, 0, 0, 16)
toast.Size = UDim2.fromOffset(460, 44)
toast.BackgroundColor3 = Color3.fromRGB(20, 34, 26)
toast.BackgroundTransparency = 0.15
toast.Font = Enum.Font.GothamBold
toast.TextSize = 18
toast.TextWrapped = true
toast.TextColor3 = Color3.new(1, 1, 1)
toast.Visible = false
toast.Parent = gui
Instance.new("UICorner", toast).CornerRadius = UDim.new(0, 12)

local dropRemote = ReplicatedStorage:WaitForChild("DropBale")
local aimRemote = ReplicatedStorage:WaitForChild("ToolAim")

-- The server runs every tool click. All the client adds is where the click pointed, so the shovel and rake
-- work on the exact hay piece or bale under the cursor. Without it they act on what is in front of you.
local mouse = player:GetMouse()
local hookedTools = setmetatable({}, { __mode = "k" })

local function sendAim()
	local ray = workspace.CurrentCamera:ScreenPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 300, params)
	if hit then
		aimRemote:FireServer(hit.Position, hit.Instance)
	end
end

local function hookTool(child)
	if child:IsA("Tool") and not hookedTools[child] then
		hookedTools[child] = true
		child.Activated:Connect(sendAim)
	end
end

-- While carrying a bale, a click on the world or G puts it down (its Put down button does the same).
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or not player:GetAttribute("Carrying") then
		return
	end
	local kind = input.UserInputType
	local pressed = kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch
	if pressed or input.KeyCode == Enum.KeyCode.G then
		dropRemote:FireServer()
	end
end)

local HINTS = {
	Shovel = "Shovel: click a bale or hay",
	Rake = "Rake: click loose hay",
}

local function refresh()
	local tool = player.Character and player.Character:FindFirstChildOfClass("Tool")
	local cash = player:GetAttribute("Cash") or 0
	local hay = player:GetAttribute("LoadHay") or 0
	local cap = player:GetAttribute("LoadCap") or 1
	local carrying = player:GetAttribute("Carrying")
	cashLabel.Text = ("$%d"):format(cash)
	if carrying then
		loadLabel.Text = "Carrying a bale"
		hintLabel.Text = "Click or G: set it down"
	else
		hintLabel.Text = tool and HINTS[tool.Name] or "Hands: press Pick up on a bale"
		loadLabel.Text = ("Hay carried %d / %d"):format(hay, cap)
	end
	bar.Size = UDim2.fromScale(math.clamp(hay / cap, 0, 1), 1)
end

local toastToken = 0
local function showToast()
	local text = player:GetAttribute("ToastText")
	if not text then
		return
	end
	toastToken += 1
	local mine = toastToken
	toast.Text = text
	toast.Visible = true
	task.delay(3.5, function()
		if toastToken == mine then
			toast.Visible = false
		end
	end)
end

for _, name in { "Cash", "LoadHay", "LoadCap", "Carrying" } do
	player:GetAttributeChangedSignal(name):Connect(refresh)
end
player:GetAttributeChangedSignal("ToastId"):Connect(showToast)

-- Equipping or putting away a tool moves it in and out of the character, so watch that for the hint.
-- The bales' Pick up buttons are for bare hands only. With a tool out they are hidden, so a click with the
-- shovel or rake goes to the tool instead of grabbing the bale. This setting only affects this player.
local CollectionService = game:GetService("CollectionService")
local promptsOn = true

local function setPrompt(bale)
	local prompt = bale:FindFirstChildOfClass("ProximityPrompt") or bale:WaitForChild("ProximityPrompt", 5)
	if prompt then
		prompt.Enabled = promptsOn
	end
end

local function updatePrompts()
	local character = player.Character
	promptsOn = not (character and character:FindFirstChildOfClass("Tool"))
	for _, bale in CollectionService:GetTagged("HayBale") do
		task.spawn(setPrompt, bale)
	end
end
CollectionService:GetInstanceAddedSignal("HayBale"):Connect(setPrompt)

local function watchCharacter(character)
	for _, child in character:GetChildren() do
		hookTool(child)
	end
	character.ChildAdded:Connect(function(child)
		hookTool(child)
		updatePrompts()
		refresh()
	end)
	character.ChildRemoved:Connect(function()
		updatePrompts()
		refresh()
	end)
	updatePrompts()
	refresh()
end
player.CharacterAdded:Connect(watchCharacter)
if player.Character then
	watchCharacter(player.Character)
end
refresh()

print("[Needlewood] client started")
