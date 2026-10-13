--!nonstrict
-- Draws the weather of the region you stand in (the server rolls it, see Services/Weather.luau): rain, snow, dust
-- or ash falling around the camera, the clouds, and the haze. The haze and grip go out as Lighting attributes on
-- this client only: WeatherTint / WeatherDensity (DayNightSky.client mixes them into the sky) and WeatherGrip
-- (Truck.client scales acceleration and braking by it). Changes blend over a few seconds.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config.Weather)
local WorldRegions = require(Shared:WaitForChild("WorldRegions"))

local player = Players.LocalPlayer

local AREA = 140 -- studs square of falling weather around the camera
local HEIGHT = 45 -- the cloud of particles starts this far above the camera
local BLEND = 0.35 -- per second, how fast the haze, clouds and grip follow a change

local emitterPart = Instance.new("Part")
emitterPart.Name = "WeatherFall"
emitterPart.Anchored = true
emitterPart.CanCollide = false
emitterPart.CanQuery = false
emitterPart.CanTouch = false
emitterPart.CastShadow = false
emitterPart.Transparency = 1
emitterPart.Size = Vector3.new(AREA, 1, AREA)

local emitter = Instance.new("ParticleEmitter")
emitter.EmissionDirection = Enum.NormalId.Bottom
emitter.LightInfluence = 0.6
emitter.Rate = 0
emitter.Parent = emitterPart

local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
if not clouds then
	clouds = Instance.new("Clouds")
	clouds.Cover = 0.25
	clouds.Density = 0.6
	clouds.Parent = workspace.Terrain
end

local current = nil -- kind id being drawn
local tint, density, grip, cover = Config.Kinds.clear.tint, 0, 1, Config.Kinds.clear.cloud

local function show(kindId)
	current = kindId
	local fall = Config.Kinds[kindId].fall
	if not fall then
		emitter.Rate = 0
		return
	end
	emitter.Color = ColorSequence.new(fall.color)
	emitter.Size = NumberSequence.new(fall.size)
	emitter.Squash = NumberSequence.new(fall.streak and 3 or 0)
	emitter.Orientation = fall.streak and Enum.ParticleOrientation.VelocityParallel or Enum.ParticleOrientation.FacingCamera
	emitter.Speed = NumberRange.new(fall.speed * 0.9, fall.speed * 1.1)
	emitter.Acceleration = Vector3.new(fall.drift, 0, fall.drift * 0.4)
	emitter.Lifetime = NumberRange.new(math.clamp((HEIGHT + 20) / math.max(fall.speed, 4), 1, 8))
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, fall.streak and 0.5 or 0.2),
		NumberSequenceKeypoint.new(0.85, fall.streak and 0.5 or 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.RotSpeed = fall.streak and NumberRange.new(0) or NumberRange.new(-60, 60)
	emitter.Rate = fall.rate
end

local regionId = "meadow"
local sinceCheck = 0

RunService.RenderStepped:Connect(function(dt)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	sinceCheck += dt
	if sinceCheck > 1 then
		sinceCheck = 0
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local region = WorldRegions.at(root and root.Position or camera.CFrame.Position)
		regionId = region and region.id or "shore" -- out at sea: the shore's weather
	end
	local kindId = ReplicatedStorage:GetAttribute("Weather_" .. regionId)
	if not Config.Kinds[kindId] then
		kindId = "clear"
	end
	if kindId ~= current then
		show(kindId)
	end

	local kind = Config.Kinds[kindId]
	local goalTint, goalDensity, goalCloud = kind.tint, kind.density, kind.cloud
	-- A front on its way here (Services/Weather.luau): the sky clouds over and darkens through the warning minute.
	local frontKind = Config.Kinds[ReplicatedStorage:GetAttribute("WeatherFrontKind")]
	if frontKind and ReplicatedStorage:GetAttribute("WeatherFront") == regionId and ReplicatedStorage:GetAttribute("WeatherFrontPhase") == "coming" then
		local left = (ReplicatedStorage:GetAttribute("WeatherFrontAt") or 0) - workspace:GetServerTimeNow()
		local p = math.clamp(1 - left / Config.FrontWarnSeconds, 0, 1)
		goalTint = goalTint:Lerp(frontKind.tint, p * 0.7)
		goalDensity = goalDensity + (frontKind.density - goalDensity) * p * 0.5
		goalCloud = math.max(goalCloud, frontKind.cloud * (0.4 + 0.6 * p))
	end
	local k = math.min(1, dt * BLEND)
	tint = tint:Lerp(goalTint, k)
	density += (goalDensity - density) * k
	grip += (kind.grip - grip) * k
	cover += (goalCloud - cover) * k
	Lighting:SetAttribute("WeatherTint", tint)
	Lighting:SetAttribute("WeatherDensity", density)
	Lighting:SetAttribute("WeatherGrip", grip)
	clouds.Cover = cover

	emitterPart.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, HEIGHT, 0))
	if emitterPart.Parent ~= camera then
		emitterPart.Parent = camera
	end
end)
