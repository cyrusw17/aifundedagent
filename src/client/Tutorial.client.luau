--!nonstrict
-- The first-time guide. A card at the top of the screen says what to do next, and a glowing line points the way.
-- Each step finishes itself when you do it. NEXT moves on anyway, SKIP ends the guide, and HELP (under the HUD)
-- plays it again. The server remembers in your save that you finished it (Tutorial.luau).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local UI = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UI")
local Kit = require(UI:WaitForChild("Kit"))
local Menus = require(UI:WaitForChild("Menus"))
local Waypoint = require(UI:WaitForChild("Waypoint"))
local Places = require(UI:WaitForChild("Places"))

local Theme = Kit.Theme
local C, F, T = Theme.Colors, Theme.Fonts, Theme.Text
local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Tutorial")
local actionRemote = remotes:WaitForChild("Action")

local function flag(name)
	for f in string.gmatch(player:GetAttribute("TutorialFlags") or "", "[^,]+") do
		if f == name then
			return true
		end
	end
	return false
end

local function nearestTagged(tag, filter)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local best, bestDistance = nil, math.huge
	for _, part in CollectionService:GetTagged(tag) do
		if part:IsA("BasePart") and part:IsDescendantOf(workspace) and (not filter or filter(part)) then
			local d = (part.Position - root.Position).Magnitude
			if d < bestDistance then
				best, bestDistance = part, d
			end
		end
	end
	return best and best.Position or nil
end

-- Each step: title, text, done() -> bool, target() -> position or nil, label for the pin.
local STEPS = {
	{
		title = "Lift a bale",
		text = "Walk up to a hay bale and press F to pick it up.",
		done = function()
			return player:GetAttribute("Carrying") == true
		end,
		target = function()
			return nearestTagged("HayBale")
		end,
		label = "Hay bale",
	},
	{
		title = "Sell it",
		text = "Carry it to the glowing SELL HERE pad at the Hay Shop and set it down (click or G).",
		done = function()
			return flag("sold")
		end,
		target = function()
			return Places.get("sellpad")
		end,
		label = "Sell pad",
	},
	{
		title = "Break one open",
		text = "Take out the shovel (press 1) and click a bale. It bursts into loose hay.",
		done = function()
			return flag("broke")
		end,
		target = function()
			return nearestTagged("HayBale")
		end,
		label = "Hay bale",
	},
	{
		title = "Find a needle",
		text = "Look for a shiny needle in the spilled hay and click it to pick it up. Not every bale has one.",
		done = function()
			return (player:GetAttribute("NeedlesHeld") or 0) > 0
		end,
		target = function()
			return nearestTagged("Needle")
		end,
		label = "Needle",
	},
	{
		title = "Buy a truck",
		text = "Trucks haul many bales at once. Stand on the red rug at Hank's counter in Homestead Motors.",
		done = function()
			return (player:GetAttribute("OwnedTrucks") or "") ~= ""
		end,
		target = function()
			return Places.get("dealer")
		end,
		label = "Homestead Motors",
	},
	{
		title = "Buy land",
		text = "Stand on the rug at the Meadow Land Office counter and pick a plot.",
		done = function()
			return (player:GetAttribute("LandPlot") or 0) > 0
		end,
		target = function()
			return Places.get("landoffice")
		end,
		label = "Land Office",
	},
	{
		title = "Build a sorter",
		text = "On your plot press BUILD, then place belts and a Hand sieve. Sorted needles pay far more.",
		done = function()
			return flag("sorter")
		end,
		target = function()
			return Places.myPlot()
		end,
		label = "Your plot",
	},
}

-- Card ---------------------------------------------------------------------------------------------------------------

local gui = Kit.screen("NeedlewoodGuide", 6)
local card = Instance.new("Frame")
card.Name = "GuideCard"
card.AnchorPoint = Vector2.new(0.5, 0)
card.Position = UDim2.new(0.5, 0, 0, 100)
card.Size = UDim2.fromOffset(440, 112)
card.BackgroundColor3 = C.Paper
card.Visible = false
card.Parent = gui
Kit.corner(card, 10)
Kit.stroke(card, C.Ink, 2)
Kit.fit(card, 440, 112)

local stepLabel = Kit.label(card, "", { size = T.Small, font = F.Bold, color = C.InkSoft, wrap = false })
stepLabel.Position = UDim2.fromOffset(14, 8)
stepLabel.Size = UDim2.new(1, -28, 0, 16)
local titleLabel = Kit.label(card, "", { size = T.Title, font = F.Title, wrap = false })
titleLabel.Position = UDim2.fromOffset(14, 24)
titleLabel.Size = UDim2.new(1, -28, 0, 24)
local textLabel = Kit.label(card, "", { size = T.Body })
textLabel.Position = UDim2.fromOffset(14, 50)
textLabel.Size = UDim2.new(1, -170, 0, 54)
textLabel.TextYAlignment = Enum.TextYAlignment.Top

local nextButton = Kit.button(card, "NEXT", "go", UDim2.fromOffset(70, 30))
nextButton.AnchorPoint = Vector2.new(1, 1)
nextButton.Position = UDim2.new(1, -12, 1, -12)
local skipButton = Kit.button(card, "SKIP", "plain", UDim2.fromOffset(70, 30))
skipButton.AnchorPoint = Vector2.new(1, 1)
skipButton.Position = UDim2.new(1, -90, 1, -12)

local dots = Instance.new("Frame")
dots.AnchorPoint = Vector2.new(1, 0)
dots.Position = UDim2.new(1, -14, 0, 10)
dots.Size = UDim2.fromOffset(120, 10)
dots.BackgroundTransparency = 1
dots.Parent = card
local dotLayout = Instance.new("UIListLayout")
dotLayout.FillDirection = Enum.FillDirection.Horizontal
dotLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
dotLayout.Padding = UDim.new(0, 5)
dotLayout.Parent = dots
local dotFrames = {}
for i = 1, #STEPS do
	local d = Instance.new("Frame")
	d.Size = UDim2.fromOffset(10, 10)
	d.LayoutOrder = i
	d.BorderSizePixel = 0
	d.Parent = dots
	Kit.corner(d, 5)
	dotFrames[i] = d
end

-- Flow ---------------------------------------------------------------------------------------------------------------

local running = false
local index = 1
local finishing = false
local stepStartedDone = false -- the step was already done when it came up (shown as a check, waits for NEXT)
local runToken = 0

local function render()
	local step = STEPS[index]
	if not step then
		return
	end
	local already = stepStartedDone
	stepLabel.Text = ("STEP %d OF %d"):format(index, #STEPS)
	titleLabel.Text = (already and "✓ " or "") .. step.title
	textLabel.Text = already and "You've done this one already. Press NEXT." or step.text
	Kit.setStyle(nextButton, already and "go" or "plain")
	nextButton.Text = index == #STEPS and "FINISH" or "NEXT"
	for i, d in dotFrames do
		d.BackgroundColor3 = i < index and C.Green or i == index and C.Picked or C.CardDim
	end
end

-- The guide's own marker. The guide only moves or clears a marker it set, so one from the map, the shop or the goal
-- bar stays until the player reaches it.
local guideMark = nil
local function ours()
	local now = Waypoint.position()
	return now == nil or (guideMark ~= nil and (now - guideMark).Magnitude < 0.5)
end
local function clearGuideMark()
	if guideMark and ours() then
		Waypoint.clear()
	end
	guideMark = nil
end

-- The card hides while a menu (map, shop...) is open, so it never covers one.
local function showCard()
	card.Visible = running and Menus.current() == nil
end
Menus.changed.Event:Connect(showCard)

-- On short (phone) screens the card sits at the bottom, clear of the HUD column and the top of the menus.
local function placeCard()
	local camera = Workspace.CurrentCamera
	local view = camera and camera.ViewportSize or Vector2.new(1024, 768)
	if view.Y < 520 or view.X < 900 then
		card.AnchorPoint = Vector2.new(0.5, 1)
		card.Position = UDim2.new(0.5, 0, 1, -12)
	else
		card.AnchorPoint = Vector2.new(0.5, 0)
		card.Position = UDim2.new(0.5, 0, 0, 100)
	end
end
placeCard()
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(placeCard)
end

local function stop(markDone)
	running = false
	runToken += 1
	showCard()
	clearGuideMark()
	if markDone then
		actionRemote:FireServer("done")
	end
end

local function finish()
	finishing = true
	stepLabel.Text = "ALL DONE"
	titleLabel.Text = "You're set!"
	textLabel.Text = "Press HELP under your cash any time to see this again. The bar under it shows your next goal."
	nextButton.Text = "CLOSE"
	Kit.setStyle(nextButton, "go")
	Waypoint.clear()
end

local function enter(i)
	index = i
	finishing = false
	local step = STEPS[index]
	if not step then
		finish()
		return
	end
	stepStartedDone = step.done()
	render()
end

local function advance()
	if finishing or index >= #STEPS then
		if finishing then
			stop(true)
		else
			finish()
		end
		return
	end
	enter(index + 1)
end

local function start(fromStep)
	runToken += 1
	local token = runToken
	running = true
	showCard()
	enter(fromStep or 1)
	-- Watch for the step to get done, and keep the arrow on its target.
	task.spawn(function()
		while running and runToken == token do
			local step = STEPS[index]
			if step and not finishing then
				if not stepStartedDone and step.done() then
					titleLabel.Text = "✓ Nice!"
					local at = index
					local flash = TweenService:Create(card, TweenInfo.new(0.25), { BackgroundColor3 = C.Hay })
					flash:Play()
					task.wait(1.1)
					card.BackgroundColor3 = C.Paper
					-- Unless NEXT was pressed during the flash (that already moved on).
					if running and runToken == token and index == at and not finishing then
						advance()
					end
				else
					local ok, where = pcall(step.target)
					if ok and where and not stepStartedDone then
						if
							ours()
							and (Waypoint.position() == nil or guideMark == nil or (where - guideMark).Magnitude > 2)
						then
							Waypoint.set(where, step.label, true)
							guideMark = where
						end
					else
						clearGuideMark()
					end
				end
			end
			task.wait(0.5)
		end
	end)
end

nextButton.Activated:Connect(advance)
skipButton.Activated:Connect(function()
	stop(true)
end)

Menus.event("Help").Event:Connect(function()
	actionRemote:FireServer("replay")
	start(1)
end)

-- First run: once a save is loaded and the server says the guide isn't done yet, start at the first step not done.
local started = false
local function maybeStart()
	if started or not player:GetAttribute("SaveSlot") then
		return
	end
	local done = player:GetAttribute("TutorialDone")
	if done == nil then
		return -- the server hasn't said yet
	end
	started = true
	if done then
		return
	end
	local first = 1
	while STEPS[first] and STEPS[first].done() do
		first += 1
	end
	if STEPS[first] then
		start(first)
	else
		actionRemote:FireServer("done")
	end
end
player:GetAttributeChangedSignal("SaveSlot"):Connect(maybeStart)
player:GetAttributeChangedSignal("TutorialDone"):Connect(maybeStart)
maybeStart()
