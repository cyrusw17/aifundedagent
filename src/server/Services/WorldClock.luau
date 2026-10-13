--!nonstrict
-- The world's clock, for everything outside quests: is it night, and the lamps that come on after sunset.
-- The clock itself is DayNight.luau (Quests thread): a 20-minute day turning Lighting.ClockTime on the server. The
-- sky's colors through the day (golden hour, blue night, each region's haze) are drawn per client in
-- DayNightSky.client.luau.
--
--   WorldClock.isNight()   true from nightfall to dawn (Config/Quests Time.Windows.night), for the Corn Night Maze,
--                          the Ghost Hauler and anything else that only happens in the dark
--   WorldClock.phase()     "midnight" / "night" / "dusk" / "day", from the same Quests windows
--   WorldClock.lampsOn()   true from a little before dark to a little after dawn
--
-- Lamps: a PointLight / SpotLight inside a part named like "Lamp" or "Lantern" (LampPost, PierLamp, Lantern...) or
-- tagged "NightLamp" switches on at dusk and off at dawn, and its part glows only while lit. Tag a lamp
-- "AlwaysLit" to keep it on (cave lamps, the undersea tube).
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")

local DayNight = require(script.Parent.DayNight)
local Windows = require(game:GetService("ReplicatedStorage").Shared.Config.Quests).Time.Windows

local WorldClock = {}

local LAMPS_ON, LAMPS_OFF = 18.25, 6.25 -- game hours
local SCAN_EVERY = 20 -- seconds between looks for new lamps (plots and machines are built during play)

function WorldClock.hour()
	return DayNight.hour()
end

function WorldClock.isNight()
	return DayNight.is("night")
end

-- "midnight", "night", "dusk" or "day" (Quests' windows, the narrowest that is open now).
function WorldClock.phase()
	for _, window in { "midnight", "night", "dusk", "day" } do
		if Windows[window] and DayNight.is(window) then
			return window
		end
	end
	return "day"
end

function WorldClock.lampsOn(hour)
	hour = hour or DayNight.hour()
	return hour >= LAMPS_ON or hour < LAMPS_OFF
end

local function isLamp(light)
	local holder = light.Parent
	if not (holder and holder:IsA("BasePart")) then
		return false
	end
	if CollectionService:HasTag(holder, "AlwaysLit") or CollectionService:HasTag(light, "AlwaysLit") then
		return false
	end
	if CollectionService:HasTag(holder, "NightLamp") or CollectionService:HasTag(light, "NightLamp") then
		return true
	end
	local name = holder.Name
	return string.find(name, "Lamp") ~= nil or string.find(name, "Lantern") ~= nil
end

local lamps = {} -- light -> its part's lit material

local function setLamp(light, on)
	light.Enabled = on
	local holder = light.Parent
	if holder and holder:IsA("BasePart") then
		if lamps[light] == nil then
			lamps[light] = holder.Material
		end
		holder.Material = on and lamps[light] or Enum.Material.SmoothPlastic
	end
end

local function scan(on)
	for _, d in workspace:GetDescendants() do
		if (d:IsA("PointLight") or d:IsA("SpotLight")) and lamps[d] == nil and isLamp(d) then
			setLamp(d, on)
		end
	end
	for light in lamps do
		if not light.Parent then
			lamps[light] = nil
		end
	end
end

local started = false
function WorldClock.start()
	if started then
		return
	end
	started = true
	DayNight.start()
	-- Atmosphere for the sky script to tint (the place may not have one).
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.28
		atmosphere.Offset = 0.1
		atmosphere.Haze = 1.2
		atmosphere.Glare = 0.3
		atmosphere.Parent = Lighting
	end
	task.spawn(function()
		local on = WorldClock.lampsOn()
		scan(on)
		local sinceScan = 0
		while true do
			task.wait(1)
			sinceScan += 1
			local now = WorldClock.lampsOn()
			if now ~= on then
				on = now
				for light in lamps do
					if light.Parent then
						setLamp(light, on)
					end
				end
			end
			if sinceScan >= SCAN_EVERY then
				sinceScan = 0
				scan(on)
			end
		end
	end)
end

return WorldClock
