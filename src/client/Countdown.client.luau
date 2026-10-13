--!nonstrict
-- The HUD countdown strip (CEO "Addiction push" H2): one short line under the compass saying what is about to
-- happen, so there is always a reason to stay a few more minutes. It reads only published ReplicatedStorage and
-- player attributes:
--   RichFieldEnds / RichFieldRegion            when the rich field moves on (WorldMap.luau)
--   RegionEvent / RegionEventEnds              when the region event ends (RegionEvents.luau)
--   WeatherFront / WeatherFrontKind / Phase / At   when a front arrives or clears (Weather.luau)
--   Cash and Catalog.nextGoal()                how little is left to the next buy
-- Pick order: anything due within a minute (soonest first), then "only $X to ..." when the next buy is close, then
-- the soonest timer. Hidden when there is nothing to say; it sits in the top-center stack (UI/Hud.luau).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = Shared:WaitForChild("UI")
local Kit = require(UI:WaitForChild("Kit"))
local Hud = require(UI:WaitForChild("Hud"))
local Catalog = require(UI:WaitForChild("Catalog"))
local Map = require(Shared:WaitForChild("Config"):WaitForChild("WorldMap"))
local WeatherConfig = require(Shared.Config:WaitForChild("Weather"))
local Prices = require(Shared.Config:WaitForChild("Prices"))
local GameConfig = require(Shared.Config:WaitForChild("Game"))
local C, F = Kit.Theme.Colors, Kit.Theme.Fonts

local player = Players.LocalPlayer

local SOON = 60 -- seconds: a timer this close beats everything else
local CLOSE = 0.25 -- the next buy counts as close when at most this share of its price is left

local strip = Instance.new("Frame")
strip.Name = "Countdown"
strip.LayoutOrder = Hud.TopOrder.Countdown
strip.Size = UDim2.fromOffset(0, 26)
strip.AutomaticSize = Enum.AutomaticSize.X
strip.BackgroundColor3 = C.Ink
strip.BackgroundTransparency = 0.25
strip.Visible = false
strip.Parent = Hud.top()
Kit.corner(strip, 8)
local pad = Instance.new("UIPadding")
pad.PaddingLeft = UDim.new(0, 12)
pad.PaddingRight = UDim.new(0, 12)
pad.Parent = strip
local limit = Instance.new("UISizeConstraint")
limit.MaxSize = Vector2.new(440, 26)
limit.Parent = strip
local text = Kit.label(strip, "", { size = 14, font = F.Bold, color = C.Cream, wrap = false })
text.Size = UDim2.fromScale(0, 1)
text.AutomaticSize = Enum.AutomaticSize.X
text.TextTruncate = Enum.TextTruncate.AtEnd

local regionNames = { meadow = "Meadow Farm" }
for _, region in Map.Regions do
	regionNames[region.id] = region.name
end

-- "4:05", or "1:02:30" past an hour.
local function clock(seconds)
	seconds = math.max(0, math.ceil(seconds))
	local h, m, s = seconds // 3600, (seconds // 60) % 60, seconds % 60
	if h > 0 then
		return ("%d:%02d:%02d"):format(h, m, s)
	end
	return ("%d:%02d"):format(m, s)
end

-- Seconds until a server-time attribute, or nil when it is unset or past.
local function left(name)
	local at = ReplicatedStorage:GetAttribute(name)
	if typeof(at) ~= "number" then
		return nil
	end
	local seconds = at - Workspace:GetServerTimeNow()
	return seconds > 0 and seconds or nil
end

-- { seconds, text } for each running timer.
local function timers()
	local list = {}
	local rich = left("RichFieldEnds")
	if rich then
		local region = ReplicatedStorage:GetAttribute("RichFieldRegion")
		local where = typeof(region) == "string" and (" in " .. region) or ""
		table.insert(list, { rich, ("★ Rich field%s moves in %s"):format(where, clock(rich)) })
	end
	local event = ReplicatedStorage:GetAttribute("RegionEvent")
	local eventLeft = left("RegionEventEnds")
	if typeof(event) == "string" and event ~= "" and eventLeft then
		table.insert(list, { eventLeft, ("%s ends in %s"):format(event, clock(eventLeft)) })
	end
	local frontLeft = left("WeatherFrontAt")
	local kind = WeatherConfig.Kinds[ReplicatedStorage:GetAttribute("WeatherFrontKind")]
	local region = regionNames[ReplicatedStorage:GetAttribute("WeatherFront")]
	if frontLeft and kind and region then
		local phase = ReplicatedStorage:GetAttribute("WeatherFrontPhase")
		if phase == "coming" then
			table.insert(list, { frontLeft, ("%s reaches %s in %s"):format(kind.name, region, clock(frontLeft)) })
		elseif phase == "on" then
			table.insert(list, { frontLeft, ("%s over %s clears in %s"):format(kind.name, region, clock(frontLeft)) })
		end
	end
	table.sort(list, function(a, b)
		return a[1] < b[1]
	end)
	return list
end

-- "Only $240 to Leather Gloves" when the next buy is close (its down payment, for a truck on a loan).
local function nearGoal()
	if GameConfig.InfiniteMoney or player:GetAttribute("SaveSlot") == nil then
		return nil
	end
	local goal = Catalog.nextGoal()
	if not goal then
		return nil
	end
	local target = goal.price
	if goal.loan then
		target = math.floor(goal.price * (Prices.Bank.DownPayment or 1))
	end
	local short = target - (player:GetAttribute("Cash") or 0)
	if short > 0 and short <= target * CLOSE then
		return ("Only %s to %s"):format(Kit.money(short), goal.name)
	end
	return nil
end

local function pick()
	local list = timers()
	if list[1] and list[1][1] <= SOON then
		return list[1][2]
	end
	return nearGoal() or (list[1] and list[1][2])
end

while true do
	local line = pick()
	strip.Visible = line ~= nil
	if line then
		text.Text = line
	end
	task.wait(0.5)
end
