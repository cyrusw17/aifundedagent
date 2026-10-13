--!nonstrict
-- Rolls each region's everyday weather (Config/Weather Regions: clear, mist, fog, ash) every few minutes and
-- publishes it as a ReplicatedStorage attribute "Weather_<region id>" = kind, which every client reads
-- (Weather.client.luau draws it). Region events can force a spell: Weather.force("desert", "dust", 180).
--
-- Fronts (map #25, Config/Weather Fronts): rain over Meadow or the Swamp, snow on Snow Peak, dust in the desert. One
-- at a time: a front is announced and the sky over its region clouds up for FrontWarnSeconds ("coming"), then it
-- sets the region's weather for a few minutes ("on"). Published as ReplicatedStorage attributes WeatherFront (region
-- id), WeatherFrontKind, WeatherFrontPhase ("coming" | "on") and WeatherFrontAt (server time the phase ends).
-- Hay's wet bales read the region's kind through Weather.get (Bales.rainingOn), so a front's rain soaks loose hay.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.Weather)
local Announce = require(script.Parent.Announce)

local Weather = {}

local forcedUntil = {} -- region id -> os.clock() when a forced spell ends
local forcedKind = {} -- region id -> the kind it was forced to
local front = nil -- { region, kind, phase, ends (os.clock), def }

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

local function between(range)
	return math.random(range[1] * 60, range[2] * 60)
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
	forcedKind[regionId] = kind
end

-- The front on the map now, if any: { region, kind, phase = "coming" | "on", ends = os.clock() }.
function Weather.front()
	return front
end

local FRONT_KINDS = {}
for _, def in Config.Fronts do
	FRONT_KINDS[def.kind] = true
end

-- Is a forced spell (an event) bringing front weather anywhere right now?
local function eventFront(now)
	for id, untilT in forcedUntil do
		if now < untilT and FRONT_KINDS[forcedKind[id]] then
			return id
		end
	end
	return nil
end

local function publishFront()
	ReplicatedStorage:SetAttribute("WeatherFront", front and front.region or nil)
	ReplicatedStorage:SetAttribute("WeatherFrontKind", front and front.kind or nil)
	ReplicatedStorage:SetAttribute("WeatherFrontPhase", front and front.phase or nil)
	ReplicatedStorage:SetAttribute("WeatherFrontAt", front and (workspace:GetServerTimeNow() + (front.ends - os.clock())) or nil)
end

local function everyday(id)
	local choices = Config.Regions[id]
	return choices and roll(choices) or "clear"
end

-- Starts a front now ("coming"); `def` is one of Config.Fronts, or a random one by weight.
function Weather.startFront(def)
	if not def then
		local weights = {}
		for i, f in Config.Fronts do
			weights[i] = f.weight
		end
		def = Config.Fronts[tonumber(roll(weights)) or 1]
	end
	front = { region = def.region, kind = def.kind, phase = "coming", ends = os.clock() + Config.FrontWarnSeconds, def = def }
	publishFront()
	pcall(Announce.say, def.text, "event")
	return front
end

-- Moves the front on: coming -> on -> over. Called every few seconds; self-tests call it with `now` pushed forward.
local nextFront = nil
function Weather.stepFront(now)
	now = now or os.clock()
	if front and now >= front.ends then
		if front.phase == "coming" then
			front.phase = "on"
			front.ends = now + between(Config.FrontMinutes)
			Weather.set(front.region, front.kind)
		else
			if not (forcedUntil[front.region] and now < forcedUntil[front.region]) then
				Weather.set(front.region, everyday(front.region))
			end
			front = nil
			nextFront = now + between(Config.FrontGapMinutes)
		end
		publishFront()
	elseif not front and now >= (nextFront or 0) and not eventFront(now) then
		Weather.startFront()
	end
end

local started = false
function Weather.start()
	if started then
		return
	end
	started = true
	local nextRoll = {}
	for id in Config.Regions do
		Weather.set(id, everyday(id))
		nextRoll[id] = os.clock() + between(Config.SpellMinutes)
	end
	nextFront = os.clock() + between(Config.FrontGapMinutes)
	task.spawn(function()
		while true do
			task.wait(5)
			local now = os.clock()
			for id in Config.Regions do
				local busy = (front and front.phase == "on" and front.region == id) or now < (forcedUntil[id] or 0)
				if now >= nextRoll[id] and not busy then
					Weather.set(id, everyday(id))
					nextRoll[id] = now + between(Config.SpellMinutes)
				end
			end
			local ok, err = pcall(Weather.stepFront, now)
			if not ok then
				warn("[Needlewood] weather front: " .. tostring(err))
			end
		end
	end)
end

return Weather
