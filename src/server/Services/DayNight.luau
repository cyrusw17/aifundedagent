--!nonstrict
-- The day and night cycle. The server turns Lighting.ClockTime and every client sees it. Rituals and night quests
-- ask this module which part of the day it is. Lengths are in Config/Quests.luau (Time).
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuestConfig = require(ReplicatedStorage.Shared.Config.Quests)

local DayNight = {}

local T = QuestConfig.Time
local started = false

-- Game hour now, 0 to 24.
function DayNight.hour()
	return Lighting.ClockTime
end

local function inWindow(hour, window)
	local from, to = window[1], window[2]
	if from <= to then
		return hour >= from and hour < to
	end
	return hour >= from or hour < to -- the window wraps past midnight
end

-- window: "day", "dusk", "night" or "midnight" (Config/Quests Time.Windows). Anything else is always true.
function DayNight.is(window)
	local range = window and T.Windows[window]
	if not range then
		return true
	end
	return inWindow(DayNight.hour(), range)
end

-- Real seconds until the window next opens (0 while it is open).
function DayNight.secondsUntil(window)
	local range = window and T.Windows[window]
	if not range or inWindow(DayNight.hour(), range) then
		return 0
	end
	local hours = (range[1] - DayNight.hour()) % 24
	return hours / 24 * T.DayMinutes * 60
end

function DayNight.start()
	if started then
		return
	end
	started = true
	Lighting.ClockTime = T.StartHour
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(0.5)
			local now = os.clock()
			local hours = (now - last) / (T.DayMinutes * 60) * 24
			last = now
			Lighting.ClockTime = (Lighting.ClockTime + hours) % 24
		end
	end)
end

return DayNight
