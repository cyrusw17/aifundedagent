--!nonstrict
-- Every timed system on an accelerated clock (CEO H16): the rich field, region events, the thunderstorm, the weekly
-- festival and the Hay Market restock each publish their countdown attribute, and it moves forward when the system
-- does. Storm and festival take a pushed clock directly (Weather.stepStorm(now), Festival.refresh(t)), so hours and
-- weeks pass in a frame; the others are stepped by calling what their timer calls. Live state is put back after.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Services = script.Parent.Parent.Services
local Shared = ReplicatedStorage:WaitForChild("Shared")

local SLACK = 3 -- seconds of clock drift allowed between setting an attribute and reading it

return function(SelfTest)
	SelfTest.register("Timers", function(t)
		local Map = require(Shared.Config.WorldMap)
		local WeatherConfig = require(Shared.Config.Weather)
		local Prices = require(Shared.Config.Prices)
		local function now()
			return workspace:GetServerTimeNow()
		end
		local function near(label, value, want)
			t.check(label, typeof(value) == "number" and math.abs(value - want) <= SLACK, ("%s, wanted %s"):format(tostring(value), tostring(want)))
		end

		-- Rich field: each rotation sets RichFieldEnds RichMinutes ahead.
		local WorldMap = require(Services.WorldMap)
		if WorldMap.rotateRich then
			WorldMap.rotateRich()
			near("the rich field's end is RichMinutes ahead", ReplicatedStorage:GetAttribute("RichFieldEnds"), now() + Map.RichMinutes * 60)
		else
			t.check("the rich field rotation is available", false, "WorldMap.rotateRich missing (map not built?)")
		end

		-- Region events: running one sets RegionEventEnds; finishing clears it.
		local RegionEvents = require(Services.RegionEvents)
		local first = RegionEvents.List[1]
		local okRun = pcall(RegionEvents.run, first.id, 0.5)
		t.check("a region event runs", okRun)
		near("a 30 s event ends 30 s from now", ReplicatedStorage:GetAttribute("RegionEventEnds"), now() + 30)
		RegionEvents.finish()
		t.equal("a finished event clears its countdown", ReplicatedStorage:GetAttribute("RegionEventEnds"), nil)

		-- Thunderstorm: warning -> on -> over, then the next storm about an hour out.
		local Weather = require(Services.Weather)
		local clock = os.clock()
		Weather.startStorm()
		t.equal("a storm starts with its warning", ReplicatedStorage:GetAttribute("Storm"), "coming")
		near("it breaks after the warning", ReplicatedStorage:GetAttribute("StormStarts"), now() + WeatherConfig.StormWarnSeconds)
		near("and ends StormMinutes later", ReplicatedStorage:GetAttribute("StormEnds"), now() + WeatherConfig.StormWarnSeconds + WeatherConfig.StormMinutes * 60)
		clock += WeatherConfig.StormWarnSeconds + 1
		Weather.stepStorm(clock)
		t.equal("after the warning the storm is on", ReplicatedStorage:GetAttribute("Storm"), "on")
		t.equal("with 5x mutation odds", (Weather.needleOdds(Vector3.new(0, 5, 0))), WeatherConfig.StormMutationOdds)
		clock += WeatherConfig.StormMinutes * 60 + 1
		Weather.stepStorm(clock)
		t.equal("then it clears", ReplicatedStorage:GetAttribute("Storm"), nil)
		local nextStarts = ReplicatedStorage:GetAttribute("StormStarts")
		local gapLow = (WeatherConfig.StormEveryMinutes[1] * 60 + WeatherConfig.StormWarnSeconds) - (clock - os.clock())
		local gapHigh = (WeatherConfig.StormEveryMinutes[2] * 60 + WeatherConfig.StormWarnSeconds) - (clock - os.clock())
		t.check("and the next one is scheduled about an hour out", typeof(nextStarts) == "number" and nextStarts >= now() + gapLow - SLACK and nextStarts <= now() + gapHigh + SLACK, tostring(nextStarts))
		-- Put the live schedule back: the clock above ran ahead of real time, so step once at the real time.
		Weather.stepStorm(os.clock())

		-- Weekly festival: four weeks pass; each week moves the region on and FestivalEnds by exactly one week.
		local Festival = require(Services.Festival)
		local base = os.time()
		local last = Festival.refresh(base)
		for week = 1, 4 do
			local fest = Festival.refresh(base + week * Map.FestivalWeek)
			t.equal(("week +%d ends one week after the last"):format(week), ReplicatedStorage:GetAttribute("FestivalEnds"), last.ends + Map.FestivalWeek)
			t.check(("week +%d moves to another region"):format(week), fest.region ~= last.region, fest.region)
			t.equal(("week +%d is published"):format(week), ReplicatedStorage:GetAttribute("FestivalRegion"), fest.region)
			last = fest
		end
		Festival.refresh(base)

		-- Hay Market: each restock sets HayMarketRestockAt RestockSeconds ahead.
		local HayMarket = require(Services.HayMarket)
		HayMarket.restock()
		near("the market's next restock is RestockSeconds ahead", ReplicatedStorage:GetAttribute("HayMarketRestockAt"), now() + Prices.HayMarket.RestockSeconds)

		-- Contracts reset: not built yet (no ContractsResetAt anywhere). Reported, not failed, until it exists.
		local contracts = ReplicatedStorage:GetAttribute("ContractsResetAt")
		if contracts ~= nil then
			t.check("the contracts reset is in the future", typeof(contracts) == "number" and contracts > now(), tostring(contracts))
		end
	end)
end
