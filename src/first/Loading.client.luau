--!nonstrict
-- The loading screen. ReplicatedFirst runs this before anything else reaches the client, so it can't use
-- ReplicatedStorage config; the art id lives here. Upload blender/launch/renders/final/loading_screen.png as a
-- Decal/Image on Roblox and paste its image id below. With 0 it paints a plain sky-and-meadow backdrop instead.
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TweenService = game:GetService("TweenService")

local IMAGE_ID = 0 -- set to the uploaded loading_screen.png image id
local MIN_SECONDS = 2.5 -- keep it up long enough to read
local MAX_SECONDS = 45 -- never trap a player behind it

local TIPS = {
	"A glint in the hay means a needle.",
	"Smash a bale with the shovel to spill its hay, then rake the strands into a row.",
	"Needles hide in the hay. Sorted needles are worth far more than loose hay.",
	"Rarer hay is heavier. Better gloves let you carry it without slowing down.",
	"Back your truck up to the dock and step on UNLOAD to tip the bales onto the belt.",
	"Buy land at the Land Office, then build belts and sorters on your plot.",
	"Bales ride loose in the truck bed. Drive gently on the hills.",
}

local player = Players.LocalPlayer
local started = os.clock()

ReplicatedFirst:RemoveDefaultLoadingScreen()

local INK = Color3.fromRGB(40, 34, 28)
local HAY = Color3.fromRGB(219, 204, 153)
local HAY_MID = Color3.fromRGB(189, 168, 112)
local TWINE = Color3.fromRGB(97, 84, 66)

local gui = Instance.new("ScreenGui")
gui.Name = "LoadingScreen"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 100 -- above the save picker (50), which waits underneath until this fades
gui.Parent = player:WaitForChild("PlayerGui")

local root = Instance.new("Frame")
root.Size = UDim2.fromScale(1, 1)
root.BackgroundColor3 = Color3.fromRGB(150, 170, 196)
root.BorderSizePixel = 0
root.Active = true
root.Parent = gui

-- Painted fallback: sky gradient over a meadow strip, the same colors as the art.
local sky = Instance.new("UIGradient")
sky.Rotation = 90
sky.Color = ColorSequence.new(Color3.fromRGB(140, 168, 196), Color3.fromRGB(240, 216, 176))
sky.Parent = root
local meadow = Instance.new("Frame")
meadow.AnchorPoint = Vector2.new(0, 1)
meadow.Position = UDim2.fromScale(0, 1)
meadow.Size = UDim2.fromScale(1, 0.38)
meadow.BackgroundColor3 = Color3.fromRGB(112, 128, 82)
meadow.BorderSizePixel = 0
meadow.Parent = root
local meadowShade = Instance.new("UIGradient")
meadowShade.Rotation = 90
meadowShade.Color = ColorSequence.new(Color3.fromRGB(126, 140, 90), Color3.fromRGB(88, 104, 66))
meadowShade.Parent = meadow

local art = Instance.new("ImageLabel")
art.Size = UDim2.fromScale(1, 1)
art.BackgroundTransparency = 1
art.ScaleType = Enum.ScaleType.Crop
art.Image = IMAGE_ID ~= 0 and ("rbxassetid://" .. IMAGE_ID) or ""
art.Parent = root

-- Darken the lower part so the bar and tips read over the meadow.
local shade = Instance.new("Frame")
shade.AnchorPoint = Vector2.new(0, 1)
shade.Position = UDim2.fromScale(0, 1)
shade.Size = UDim2.fromScale(1, 0.42)
shade.BackgroundColor3 = Color3.new(0, 0, 0)
shade.BorderSizePixel = 0
shade.Parent = root
local fade = Instance.new("UIGradient")
fade.Rotation = 90
fade.Transparency = NumberSequence.new(1, 0.45)
fade.Parent = shade

local function label(text, font, size, y, color, strokeT)
	local l = Instance.new("TextLabel")
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Position = UDim2.fromScale(0.5, y)
	l.Size = UDim2.new(0.9, 0, 0, size + 8)
	l.BackgroundTransparency = 1
	l.Font = font
	l.Text = text
	l.TextSize = size
	l.TextScaled = false
	l.TextWrapped = true
	l.TextColor3 = color
	l.TextStrokeColor3 = INK
	l.TextStrokeTransparency = strokeT
	l.Parent = root
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = size
	cap.Parent = l
	return l
end

local title = label("NEEDLEWOOD", Enum.Font.GothamBlack, 72, 0.2, Color3.new(1, 1, 1), 0.2)
title.TextScaled = true
title.Size = UDim2.new(0.8, 0, 0.12, 0)
label("HAUL HAY. FIND THE NEEDLES.", Enum.Font.GothamBold, 24, 0.29, HAY, 0.3)

local tip = label("", Enum.Font.GothamMedium, 18, 0.9, Color3.fromRGB(236, 226, 200), 0.6)

-- Progress bar: a twine-dark track with a hay fill, like a bale band.
local track = Instance.new("Frame")
track.AnchorPoint = Vector2.new(0.5, 0.5)
track.Position = UDim2.fromScale(0.5, 0.83)
track.Size = UDim2.new(0.5, 0, 0, 16)
track.BackgroundColor3 = TWINE
track.BorderSizePixel = 0
track.Parent = root
Instance.new("UICorner", track).CornerRadius = UDim.new(0, 8)
local trackStroke = Instance.new("UIStroke", track)
trackStroke.Color = INK
trackStroke.Thickness = 2
local cap = Instance.new("UISizeConstraint", track)
cap.MinSize = Vector2.new(220, 16)
cap.MaxSize = Vector2.new(640, 16)
local fill = Instance.new("Frame")
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = HAY
fill.BorderSizePixel = 0
fill.Parent = track
Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 8)
local fillShade = Instance.new("UIGradient")
fillShade.Rotation = 90
fillShade.Color = ColorSequence.new(HAY, HAY_MID)
fillShade.Parent = fill

local status = label("Loading the meadow...", Enum.Font.GothamBold, 16, 0.785, Color3.new(1, 1, 1), 0.4)

if IMAGE_ID ~= 0 then
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync({ art })
		end)
	end)
end

-- Tips rotate every few seconds.
local tipIndex = math.random(1, #TIPS)
tip.Text = TIPS[tipIndex]
task.spawn(function()
	while gui.Parent do
		task.wait(5)
		tipIndex = tipIndex % #TIPS + 1
		tip.Text = TIPS[tipIndex]
	end
end)

-- Progress: the asset queue drains while the place streams in. The bar only moves forward.
local shown = 0
local peakQueue = 1
local function setProgress(p)
	shown = math.max(shown, math.clamp(p, 0, 1))
	TweenService:Create(fill, TweenInfo.new(0.25), { Size = UDim2.fromScale(shown, 1) }):Play()
end

while os.clock() - started < MAX_SECONDS do
	local queue = ContentProvider.RequestQueueSize
	peakQueue = math.max(peakQueue, queue)
	local loaded = game:IsLoaded()
	local assets = 1 - queue / peakQueue
	setProgress((loaded and 0.5 or 0.1) + assets * 0.5 * (loaded and 1 or 0.6))
	if loaded and queue == 0 and os.clock() - started >= MIN_SECONDS then
		break
	end
	task.wait(0.1)
end

status.Text = "Ready"
setProgress(1)
task.wait(0.35)

local out = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
for _, d in ipairs(gui:GetDescendants()) do
	if d:IsA("Frame") then
		TweenService:Create(d, out, { BackgroundTransparency = 1 }):Play()
	elseif d:IsA("ImageLabel") then
		TweenService:Create(d, out, { ImageTransparency = 1 }):Play()
	elseif d:IsA("TextLabel") then
		TweenService:Create(d, out, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	elseif d:IsA("UIStroke") then
		TweenService:Create(d, out, { Transparency = 1 }):Play()
	end
end
TweenService:Create(root, out, { BackgroundTransparency = 1 }):Play()
task.wait(0.65)
gui:Destroy()
