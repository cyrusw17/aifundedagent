--!nonstrict
-- Client entry point. Shows the HUD only. The client never decides what was found or earned.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local Kit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UI"):WaitForChild("Kit"))
local Theme = Kit.Theme
local C, F = Theme.Colors, Theme.Fonts

local gui = Kit.screen("NeedlewoodHud", 4)

-- The HUD card: cash, what you carry, a load bar and a one-line hint. The goal bar and the MAP / SHOP / HELP
-- buttons sit right under it (Menus.client.luau).
local Hud = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UI"):WaitForChild("Hud"))
local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(230, 112)
panel.LayoutOrder = Hud.Order.Cash
panel.BackgroundColor3 = C.Wood
panel.BackgroundTransparency = 0.1
panel.Parent = Hud.column()
Kit.corner(panel, 10)
Kit.stroke(panel, C.Ink, 1.5)

local function makeLabel(y, size)
	local label = Instance.new("TextLabel")
	label.Position = UDim2.fromOffset(12, y)
	label.Size = UDim2.new(1, -24, 0, size)
	label.BackgroundTransparency = 1
	label.Font = F.Bold
	label.TextSize = size - 6
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = C.Cream
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Parent = panel
	return label
end

local cashLabel = makeLabel(8, 30)
cashLabel.Font = F.Title
cashLabel.TextColor3 = C.Cash
local loadLabel = makeLabel(40, 22)

local barBack = Instance.new("Frame")
barBack.Position = UDim2.fromOffset(12, 66)
barBack.Size = UDim2.new(1, -24, 0, 10)
barBack.BackgroundColor3 = C.Ink
barBack.BorderSizePixel = 0
barBack.Parent = panel
Kit.corner(barBack, 5)

local bar = Instance.new("Frame")
bar.Size = UDim2.fromScale(0, 1)
bar.BackgroundColor3 = C.Hay
bar.BorderSizePixel = 0
bar.Parent = barBack
Kit.corner(bar, 5)

-- One line saying what a click does with what is in your hands right now.
local hintLabel = makeLabel(82, 22)
hintLabel.Font = F.Medium
hintLabel.TextColor3 = C.Cream
hintLabel.TextTransparency = 0.15

-- Short messages from the server (sales, purchases) at the top of the screen.
local toast = Instance.new("TextLabel")
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.new(0.5, 0, 0, 16)
toast.Size = UDim2.fromOffset(440, 0)
toast.AutomaticSize = Enum.AutomaticSize.Y
toast.BackgroundColor3 = C.Wood
toast.BackgroundTransparency = 0.05
toast.Font = F.Bold
toast.TextSize = 16
toast.TextWrapped = true
toast.TextColor3 = C.Cream
toast.Visible = false
toast.Parent = gui
Kit.corner(toast, 10)
Kit.stroke(toast, C.Ink, 1.5)
Kit.pad(toast, 10)

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

-- On a phone a tool fires on a tap, and the mouse may still sit where an earlier touch left it. The tap's own spot
-- in the world is the truth, so it is sent too (the server uses the newest aim it has).
UserInputService.TouchTapInWorld:Connect(function(position, gameProcessed)
	local character = player.Character
	if gameProcessed or not (character and character:FindFirstChildOfClass("Tool")) then
		return
	end
	local ray = workspace.CurrentCamera:ViewportPointToRay(position.X, position.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 300, params)
	if hit then
		aimRemote:FireServer(hit.Position, hit.Instance)
	end
end)

local function hookTool(child)
	if child:IsA("Tool") and not hookedTools[child] then
		hookedTools[child] = true
		child.Activated:Connect(sendAim)
	end
end

-- Setting a carried bale down or throwing it (click, G, tap, hold to charge) is in Throw.client.luau.

local HINTS = {
	Shovel = "Shovel: %s hay or a bale; a truck bed or belt pours",
	Rake = "Rake: %s loose hay; toward a belt feeds it",
	Wheelbarrow = "Barrow: %s a bale, a truck bed, or the ground",
}

-- "tap" on a phone, "click" everywhere else.
local function verb()
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled and "tap" or "click"
end

local function refresh()
	local tool = player.Character and player.Character:FindFirstChildOfClass("Tool")
	local cash = player:GetAttribute("Cash") or 0
	local hay = player:GetAttribute("LoadHay") or 0
	local cap = (player:GetAttribute("LoadCap") or 1) + (player:GetAttribute("LoadCapBonus") or 0)
	local carrying = player:GetAttribute("Carrying")
	cashLabel.Text = Kit.money(cash)
	if carrying then
		loadLabel.Text = "Carrying a bale"
		hintLabel.Text = if verb() == "tap" then "Tap: set it down. Hold THROW: throw" else "Click: set down. Hold: throw"
	else
		hintLabel.Text = tool and HINTS[tool.Name] and HINTS[tool.Name]:format(verb()) or "Hands: press Pick up on a bale"
		loadLabel.Text = ("Hay %d / %d · %s"):format(hay, cap, player:GetAttribute("GloveName") or "Bare hands")
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

-- The glove stand's buttons read Buy for pairs you do not own, Wear for ones you do, Wearing for the pair on.
local function updateGlovePrompts()
	local owned = {}
	for id in string.gmatch(player:GetAttribute("GlovesOwned") or "", "[^,]+") do
		owned[id] = true
	end
	local wearing = player:GetAttribute("GloveId")
	for _, prompt in workspace:GetDescendants() do
		if prompt:IsA("ProximityPrompt") and prompt.Name == "GlovePrompt" then
			local id = prompt:GetAttribute("GloveId")
			if id == wearing then
				prompt.ActionText = "Wearing"
			elseif owned[id] then
				prompt.ActionText = "Wear"
			else
				prompt.ActionText = ("Buy $%d"):format(prompt:GetAttribute("Price") or 0)
			end
		end
	end
end
player:GetAttributeChangedSignal("GlovesOwned"):Connect(updateGlovePrompts)
player:GetAttributeChangedSignal("GloveId"):Connect(updateGlovePrompts)
workspace.DescendantAdded:Connect(function(d)
	if d:IsA("ProximityPrompt") and d.Name == "GlovePrompt" then
		task.defer(updateGlovePrompts)
	end
end)

for _, name in { "Cash", "LoadHay", "LoadCap", "LoadCapBonus", "Carrying", "GloveName" } do
	player:GetAttributeChangedSignal(name):Connect(refresh)
end
player:GetAttributeChangedSignal("ToastId"):Connect(showToast)

-- Equipping or putting away a tool moves it in and out of the character, so watch that for the hint.
-- The bales' Pick up buttons are for bare hands only. With a tool out they are hidden, so a click with the
-- shovel or rake goes to the tool instead of grabbing the bale. This setting only affects this player.
local CollectionService = game:GetService("CollectionService")
local promptsOn = true

-- Shown only with bare hands and while the server says the bale can be picked up (not breaking or in a barrow).
local hookedPrompts = setmetatable({}, { __mode = "k" })
local function applyPrompt(prompt)
	local want = promptsOn and prompt:GetAttribute("Usable") ~= false
	if prompt.Enabled ~= want then
		prompt.Enabled = want
	end
end

local function setPrompt(bale)
	local prompt = bale:FindFirstChildOfClass("ProximityPrompt") or bale:WaitForChild("ProximityPrompt", 5)
	if not prompt then
		return
	end
	if not hookedPrompts[prompt] then
		hookedPrompts[prompt] = true
		-- The server turns the button back on when a bale is released; keep this player's rule on top of that.
		prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
			applyPrompt(prompt)
		end)
		prompt:GetAttributeChangedSignal("Usable"):Connect(function()
			applyPrompt(prompt)
		end)
	end
	applyPrompt(prompt)
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
