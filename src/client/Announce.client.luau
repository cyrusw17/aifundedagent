--!nonstrict
-- Server-wide banners (Announce.luau): a strip that slides down from the top of the screen for a few seconds.
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UI = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UI")
local Kit = require(UI:WaitForChild("Kit"))
local Sounds = require(ReplicatedStorage.Shared.Config:WaitForChild("Sounds"))

local C, F = Kit.Theme.Colors, Kit.Theme.Fonts
local SHOW = 4.5

local gui = Kit.screen("NeedlewoodAnnounce", 8)

local banner = Instance.new("Frame")
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0, -60)
banner.Size = UDim2.fromOffset(0, 40)
banner.AutomaticSize = Enum.AutomaticSize.X
banner.BackgroundColor3 = C.Ink
banner.BackgroundTransparency = 0.1
banner.Visible = false
banner.Parent = gui
Kit.corner(banner, 10)
local edge = Kit.stroke(banner, C.Hay, 2)
local pad = Instance.new("UIPadding")
pad.PaddingLeft = UDim.new(0, 18)
pad.PaddingRight = UDim.new(0, 18)
pad.Parent = banner
local text = Kit.label(banner, "", { size = 16, font = F.Bold, color = C.Cream, wrap = false })
text.Size = UDim2.fromScale(0, 1)
text.AutomaticSize = Enum.AutomaticSize.X
local limit = Instance.new("UISizeConstraint")
limit.MaxSize = Vector2.new(560, 40)
limit.Parent = banner
text.TextTruncate = Enum.TextTruncate.AtEnd
Kit.fit(banner, 560, 40)

local LOOKS = {
	gold = { Color3.fromRGB(250, 214, 110), Color3.fromRGB(250, 214, 110) },
	event = { C.Cream, C.Green },
}

local shown = 0
local function show(message, kind)
	if typeof(message) ~= "string" then
		return
	end
	local look = LOOKS[kind] or { C.Cream, C.Hay }
	text.Text = message
	text.TextColor3 = look[1]
	edge.Color = look[2]
	shown += 1
	local mine = shown
	banner.Visible = true
	banner.Position = UDim2.new(0.5, 0, 0, -60)
	TweenService:Create(banner, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Position = UDim2.new(0.5, 0, 0, 8) })
		:Play()
	if kind == "gold" then
		local def = Sounds.NeedleDing
		local sound = Instance.new("Sound")
		sound.SoundId = def.id
		sound.Volume = def.volume
		sound.PlaybackSpeed = 1.8
		sound.Parent = SoundService
		sound:Play()
		sound.Ended:Once(function()
			sound:Destroy()
		end)
	end
	task.delay(SHOW, function()
		if mine ~= shown then
			return
		end
		local out = TweenService:Create(banner, TweenInfo.new(0.3), { Position = UDim2.new(0.5, 0, 0, -60) })
		out:Play()
		out.Completed:Once(function()
			if mine == shown then
				banner.Visible = false
			end
		end)
	end)
end

local remote = ReplicatedStorage:WaitForChild("Announce")
remote.OnClientEvent:Connect(show)
