--!nonstrict
-- The sound of where you are: a wind loop and a water loop under everything, mixed per region (Config/Sounds
-- RegionAmbience) and cross-faded over a few seconds as you walk or drive into another one. Rain in your region adds
-- to the water. Both play through SoundService, so the Settings sound slider covers them.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Sounds = require(Shared:WaitForChild("Config"):WaitForChild("Sounds"))
local WorldRegions = require(Shared:WaitForChild("WorldRegions"))

local player = Players.LocalPlayer

local FADE = 0.5 -- per second, how fast the mix follows a change
local RAIN_WATER = 0.6 -- water share added by rain

local function loop(name, def)
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = def.id
	s.Looped = true
	s.Volume = 0
	s.PlaybackSpeed = def.pitch or 1
	s.Parent = SoundService
	s:Play()
	return s
end
local wind = loop("AmbientWind", Sounds.AmbientWind)
local water = loop("AmbientWater", Sounds.AmbientWater)

local mix = { wind = 0, water = 0, windPitch = Sounds.AmbientWind.pitch }
local target = Sounds.RegionAmbience.meadow
local regionId = "meadow"
local sinceCheck = 1

RunService.Heartbeat:Connect(function(dt)
	sinceCheck += dt
	if sinceCheck >= 1 then
		sinceCheck = 0
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local camera = workspace.CurrentCamera
		local at = root and root.Position or (camera and camera.CFrame.Position)
		if at then
			local region = WorldRegions.at(at)
			regionId = region and region.id or "shore" -- out at sea: the shore's sound
			target = Sounds.RegionAmbience[regionId] or Sounds.RegionAmbience.meadow
		end
	end
	local rain = ReplicatedStorage:GetAttribute("Weather_" .. regionId) == "rain" and RAIN_WATER or 0
	local k = math.min(1, dt * FADE)
	mix.wind += (target.wind - mix.wind) * k
	mix.water += (math.min(1, target.water + rain) - mix.water) * k
	mix.windPitch += (target.windPitch - mix.windPitch) * k
	wind.Volume = Sounds.AmbientWind.volume * mix.wind
	water.Volume = Sounds.AmbientWater.volume * mix.water
	wind.PlaybackSpeed = mix.windPitch
end)
