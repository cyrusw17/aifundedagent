--!nonstrict
-- The sky's colors through the day, drawn on this client from Lighting.ClockTime (which the server turns, see
-- WorldClock.luau): a pale blue morning, a warm golden hour before sunset (the screenshot moment), a violet dusk and a
-- deep blue night. By day the haze takes the tint of the region you stand in (Config/WorldMap style.fog, from the
-- STYLE.md region sheet). Weather.client.luau thickens it by setting Lighting attributes WeatherDensity and
-- WeatherTint (a Color3) on this client.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WorldRegions = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WorldRegions"))

local player = Players.LocalPlayer

local rgb = Color3.fromRGB
-- Keyframes by game hour. haze nil = the region's own tint at that hour.
local KEYS = {
	{ hour = 0, brightness = 0.6, outdoor = rgb(58, 64, 92), ambient = rgb(40, 44, 64), shift = rgb(0, 0, 0), haze = rgb(52, 60, 92), density = 0.36 },
	{ hour = 5, brightness = 0.8, outdoor = rgb(72, 76, 104), ambient = rgb(46, 48, 66), shift = rgb(0, 0, 0), haze = rgb(70, 74, 104), density = 0.36 },
	{ hour = 6.5, brightness = 1.8, outdoor = rgb(150, 128, 118), ambient = rgb(84, 76, 72), shift = rgb(236, 170, 130), haze = rgb(222, 178, 150), density = 0.33 },
	{ hour = 9, brightness = 2.4, outdoor = rgb(136, 136, 130), ambient = rgb(92, 90, 86), shift = rgb(0, 0, 0), haze = nil, density = 0.28 },
	{ hour = 16, brightness = 2.4, outdoor = rgb(136, 136, 130), ambient = rgb(92, 90, 86), shift = rgb(0, 0, 0), haze = nil, density = 0.28 },
	{ hour = 17.75, brightness = 2.2, outdoor = rgb(196, 150, 104), ambient = rgb(104, 86, 70), shift = rgb(255, 186, 112), haze = rgb(242, 190, 136), density = 0.3 },
	{ hour = 19.25, brightness = 1.2, outdoor = rgb(118, 92, 112), ambient = rgb(70, 58, 72), shift = rgb(180, 110, 120), haze = rgb(150, 108, 124), density = 0.33 },
	{ hour = 20.5, brightness = 0.6, outdoor = rgb(58, 64, 92), ambient = rgb(40, 44, 64), shift = rgb(0, 0, 0), haze = rgb(52, 60, 92), density = 0.36 },
}

local function between(hour)
	for i = 1, #KEYS do
		local a = KEYS[i]
		local b = KEYS[i + 1] or KEYS[1]
		local bh = i < #KEYS and b.hour or b.hour + 24
		if hour >= a.hour and hour < bh then
			local t = (hour - a.hour) / (bh - a.hour)
			return a, b, t * t * (3 - 2 * t)
		end
	end
	return KEYS[1], KEYS[1], 0
end

local regionFog = WorldRegions.Meadow.style.fog
local targetFog = regionFog
local regionDensity, targetDensity = 0, 0 -- a region's own thicker (Swamp, Haunted Grove) or clearer (Sky) air
local lastRegionCheck = 0

RunService.RenderStepped:Connect(function(dt)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	lastRegionCheck += dt
	if lastRegionCheck > 1 then
		lastRegionCheck = 0
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local region = root and WorldRegions.at(root.Position)
		if region and region.style then
			targetFog = region.style.fog
		end
	end
	-- Crossing into a region, its haze drifts in over a few seconds rather than snapping.
	regionFog = regionFog:Lerp(targetFog, math.min(1, dt * 0.4))
	regionDensity += (targetDensity - regionDensity) * math.min(1, dt * 0.4)

	local a, b, t = between(Lighting.ClockTime)
	Lighting.Brightness = a.brightness + (b.brightness - a.brightness) * t
	Lighting.OutdoorAmbient = a.outdoor:Lerp(b.outdoor, t)
	Lighting.Ambient = a.ambient:Lerp(b.ambient, t)
	Lighting.ColorShift_Top = a.shift:Lerp(b.shift, t)
	if atmosphere then
		local haze = (a.haze or regionFog):Lerp(b.haze or regionFog, t)
		local density = a.density + (b.density - a.density) * t + regionDensity
		local weatherTint = Lighting:GetAttribute("WeatherTint")
		local weatherDensity = Lighting:GetAttribute("WeatherDensity") or 0
		if typeof(weatherTint) == "Color3" and weatherDensity > 0 then
			haze = haze:Lerp(weatherTint, math.clamp(weatherDensity * 1.5, 0, 0.8))
		end
		atmosphere.Color = haze
		atmosphere.Decay = haze:Lerp(Color3.new(0, 0, 0), 0.35)
		atmosphere.Density = math.clamp(density + weatherDensity, 0, 0.85)
	end
end)
