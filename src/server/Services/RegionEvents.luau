--!nonstrict
-- One event at a time somewhere on the Stitched Isles, every Prices.RegionEvents.EveryMinutes: Hay Fever on the
-- Meadow Shore, Windfall in the Pine Forest, a Sandstorm on the Dunes, an Avalanche on Snow Peak, Low Tide in the
-- Swamp, an Eruption on the Volcano and, at night only, a Meteor Shower over Mirror Lake Valley.
-- Each one is announced server-wide, sets the region's weather (Weather.force) and drops extra bales of that region's
-- hay near its fields, worth more needles (NeedleBoost, amounts in Prices.RegionEvents). Bales nobody has touched
-- when it ends are taken away again. ReplicatedStorage attributes RegionEvent (name) and RegionEventAt (Vector3) tell
-- map screens where it is.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Map = require(Shared.Config.WorldMap)
local Prices = require(Shared.Config.Prices)
local Bales = require(script.Parent.Bales)
local Regions = require(script.Parent.Regions)
local WorldShape = require(script.Parent.WorldShape)
local Weather = require(script.Parent.Weather)
local WorldClock = require(script.Parent.WorldClock)
local Announce = require(script.Parent.Announce)

local RegionEvents = {}

RegionEvents.List = {
	{ id = "hay_fever", name = "Hay Fever", region = "shore", weather = "mist", text = "Hay Fever on the %s! The grass has burst into bales. Up to %sx needles." },
	{ id = "windfall", name = "Windfall", region = "pine", weather = "rain", text = "Windfall in the %s! The gale brought bales down off the ridge. Up to %sx needles." },
	{ id = "sandstorm", name = "Sandstorm", region = "desert", weather = "dust", text = "Sandstorm over the %s! Buried bales are coming up. %sx needles." },
	{ id = "avalanche", name = "Avalanche", region = "snow", weather = "snow", text = "Avalanche on %s! Bales tumbled down to the lodge. %sx needles." },
	{ id = "low_tide", name = "Low Tide", region = "swamp", weather = "mist", text = "Low Tide in the %s! Sunken bales are out of the water. %sx needles." },
	{ id = "eruption", name = "Eruption", region = "volcano", weather = "ash", text = "The %s is erupting! Scorched bales on the slopes, %sx needles." },
	{ id = "meteor_shower", name = "Meteor Shower", region = "valley", weather = "clear", night = true, hay = "star", text = "Meteor Shower over %s! Star hay fell into the fields, glowing. %sx needles." },
}

local SPREAD = 26 -- studs around a field's center the event's bales land
local ROAD_CLEAR = 9 -- no event bale lands closer than this to a road's center line

local regionById = {}
for _, r in Map.Regions do
	regionById[r.id] = r
end

local running = nil -- { def, bales = {b = true}, ends }

local function landingSpots(region, count, rng)
	local fields = {}
	for _, entry in Regions.fields do
		if entry.region == region.name then
			table.insert(fields, entry)
		end
	end
	local spots = {}
	if #fields == 0 then
		return spots
	end
	for _ = 1, count * 8 do
		if #spots >= count then
			break
		end
		local entry = fields[rng:NextInteger(1, #fields)]
		local x = entry.center.X + rng:NextNumber(-SPREAD, SPREAD)
		local z = entry.center.Z + rng:NextNumber(-SPREAD, SPREAD)
		local road = WorldShape.nearestRoad(x, z)
		local clear = not road or road > ROAD_CLEAR
		for _, s in spots do
			if (Vector2.new(s.X, s.Z) - Vector2.new(x, z)).Magnitude < 5.5 then
				clear = false
			end
		end
		if clear then
			table.insert(spots, Vector3.new(x, WorldShape.heightAt(x, z), z))
		end
	end
	return spots
end

-- A falling star: a glowing ball streaks down to where a bale lands.
local function streak(target, parent)
	local ball = Instance.new("Part")
	ball.Name = "FallingStar"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(2, 2, 2)
	ball.Material = Enum.Material.Neon
	ball.Color = Color3.fromRGB(255, 226, 150)
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CFrame = CFrame.new(target + Vector3.new(120, 260, -60))
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.9, 0)
	a0.Parent = ball
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.9, 0)
	a1.Parent = ball
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Lifetime = 0.6
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 236, 190))
	trail.LightEmission = 1
	trail.Parent = ball
	ball.Parent = parent
	local tween = TweenService:Create(ball, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(target + Vector3.new(0, 3, 0)) })
	tween:Play()
	tween.Completed:Wait()
	ball:Destroy()
end

local function finish()
	local event = running
	if not event then
		return
	end
	running = nil
	for b in event.bales do
		-- Untouched: still lying where it landed, nobody's, not carried.
		if not b.gone and not b.carriedBy and not b.ownerId and b.body.Parent and (b.body.Position - b.spawnPosition).Magnitude < 6 then
			Bales.consume(b)
		end
	end
	ReplicatedStorage:SetAttribute("RegionEvent", nil)
	ReplicatedStorage:SetAttribute("RegionEventAt", nil)
end

-- Starts an event now (by id); returns the bales it dropped. Ends any running event first.
function RegionEvents.run(id, minutes)
	local def
	for _, e in RegionEvents.List do
		if e.id == id then
			def = e
		end
	end
	assert(def, "unknown region event " .. tostring(id))
	finish()
	local region = regionById[def.region]
	local reward = Prices.RegionEvents[def.id]
	local seconds = (minutes or Prices.RegionEvents.Minutes) * 60
	local rng = Random.new()
	local event = { def = def, bales = {}, ends = os.clock() + seconds }
	running = event

	Weather.force(def.region, def.weather, seconds)
	local spots = landingSpots(region, reward.bales, rng)
	local folder = workspace:FindFirstChild("Needlewood")
	for _, spot in spots do
		if def.id == "meteor_shower" then
			task.spawn(streak, spot, folder or workspace)
		end
		local b = Bales.spawn(spot - Vector3.new(0, 0.35, 0), false, true, def.hay or region.hayType)
		if b then
			if def.hay == "star" then
				-- Fallen stars glow so they can be found in the dark.
				local glow = Instance.new("PointLight")
				glow.Color = Color3.fromRGB(255, 226, 150)
				glow.Range = 14
				glow.Brightness = 1.5
				glow.Parent = b.body
			end
			b.body:SetAttribute("NeedleBoost", reward.boost)
			b.body:SetAttribute("RegionEvent", def.id)
			event.bales[b] = true
		end
	end
	local center = spots[1] or Vector3.new(region.center.X, region.base, region.center.Y)
	ReplicatedStorage:SetAttribute("RegionEvent", def.name)
	ReplicatedStorage:SetAttribute("RegionEventAt", center)
	Announce.say(def.text:format(region.name, tostring(reward.boost)), "event")

	task.delay(seconds, function()
		if running == event then
			finish()
		end
	end)
	return event.bales
end

function RegionEvents.current()
	return running and running.def or nil
end

RegionEvents.finish = finish

local started = false
function RegionEvents.start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		local last = nil
		while true do
			task.wait(Prices.RegionEvents.EveryMinutes * 60)
			local choices = {}
			for _, e in RegionEvents.List do
				if e.id ~= last and (not e.night or WorldClock.isNight()) then
					table.insert(choices, e)
				end
			end
			local pick = choices[math.random(1, #choices)]
			last = pick.id
			local ok, err = pcall(RegionEvents.run, pick.id)
			if not ok then
				warn("[Needlewood] region event " .. pick.id .. " failed: " .. tostring(err))
			end
		end
	end)
end

return RegionEvents
