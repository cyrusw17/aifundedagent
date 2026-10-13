--!nonstrict
-- Rolls each region's weather (Config/Weather) every few minutes and publishes it as a ReplicatedStorage attribute
-- "Weather_<region id>" = kind, which every client reads (Weather.client.luau draws it). Region events can force a
-- spell: Weather.force("desert", "dust", 180) for a Sandstorm. Visual and road grip only.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.Weather)

local Weather = {}

local forcedUntil = {} -- region id -> os.clock() when a forced spell ends

local function roll(choices)
	local total = 0
	for _, w in choices do
		total += w
	end
	local pick = math.random() * total
	for kind, w in choices do
		pick -= w
		if pick <= 0 then
			return kind
		end
	end
	return "clear"
end

function Weather.get(regionId)
	return ReplicatedStorage:GetAttribute("Weather_" .. regionId) or "clear"
end

function Weather.set(regionId, kind)
	assert(Config.Kinds[kind], "unknown weather " .. tostring(kind))
	ReplicatedStorage:SetAttribute("Weather_" .. regionId, kind)
end

-- Hold a region's weather for `seconds` (an event); it rolls normally afterwards.
function Weather.force(regionId, kind, seconds)
	Weather.set(regionId, kind)
	forcedUntil[regionId] = os.clock() + seconds
end

local started = false
function Weather.start()
	if started then
		return
	end
	started = true
	local nextRoll = {}
	for id, choices in Config.Regions do
		Weather.set(id, roll(choices))
		nextRoll[id] = os.clock() + math.random(Config.SpellMinutes[1] * 60, Config.SpellMinutes[2] * 60)
	end
	task.spawn(function()
		while true do
			task.wait(5)
			local now = os.clock()
			for id, choices in Config.Regions do
				if now >= nextRoll[id] and now >= (forcedUntil[id] or 0) then
					Weather.set(id, roll(choices))
					nextRoll[id] = now + math.random(Config.SpellMinutes[1] * 60, Config.SpellMinutes[2] * 60)
				end
			end
		end
	end)
end

return Weather
