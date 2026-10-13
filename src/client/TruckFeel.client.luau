--!nonstrict
-- How driving feels from this client: dust off the rear wheels of every truck rolling over dirt, grass, sand or snow,
-- and, while you drive, a camera that eases back and widens a little with speed so a fast truck reads as fast.
-- Everything here is local and visual: the emitters are made on this client and nothing is sent to the server.
-- StreamingEnabled-safe: trucks are found by their TruckModel tag (Vehicles.build) as they stream in, and dropped when
-- they stream out. Nothing here walks the Workspace.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local DUST_RANGE = 220 -- only trucks this close to the camera kick up dust
local DUST_FROM = 8 -- studs per second before any dust shows
local DUST_FULL = 40 -- full dust at this speed
local BASE_FOV = 70
local FAST_FOV = 80 -- at top speed
local BASE_ZOOM = 0.5 -- Roblox's default minimum zoom
local FAST_ZOOM = 26 -- the camera is held at least this far back at top speed

-- Dust color by what the wheels roll on. Paved and rocky ground throws none.
local DUST = {
	[Enum.Material.Ground] = Color3.fromRGB(150, 122, 92),
	[Enum.Material.Mud] = Color3.fromRGB(110, 84, 60),
	[Enum.Material.Grass] = Color3.fromRGB(150, 140, 100),
	[Enum.Material.LeafyGrass] = Color3.fromRGB(150, 140, 100),
	[Enum.Material.Sand] = Color3.fromRGB(214, 190, 140),
	[Enum.Material.Sandstone] = Color3.fromRGB(200, 160, 120),
	[Enum.Material.Snow] = Color3.fromRGB(240, 244, 248),
	[Enum.Material.Salt] = Color3.fromRGB(235, 230, 220),
	[Enum.Material.CrackedLava] = Color3.fromRGB(90, 80, 75),
}

local trucks = {} -- model -> { emitters = { ParticleEmitter }, params = RaycastParams }

local function makeEmitter(chassis, offset)
	local attachment = Instance.new("Attachment")
	attachment.Name = "DustAttachment"
	attachment.Position = offset
	attachment.Parent = chassis
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "WheelDust"
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.8, 1.6)
	emitter.Speed = NumberRange.new(2, 5)
	emitter.SpreadAngle = Vector2.new(35, 35)
	emitter.Acceleration = Vector3.new(0, 3, 0)
	emitter.Drag = 2
	emitter.LightEmission = 0
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 4.5) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	emitter.EmissionDirection = Enum.NormalId.Back
	emitter.Parent = attachment
	return emitter
end

local function track(model)
	if trucks[model] then
		return
	end
	local chassis = model.PrimaryPart
	if not chassis then
		return
	end
	local length = model:GetAttribute("Length") or 24
	local trackX = model:GetAttribute("Track") or 4
	local below = -(chassis.Size.Y / 2 + 1.2)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model }
	params.IgnoreWater = false
	trucks[model] = {
		chassis = chassis,
		params = params,
		emitters = {
			makeEmitter(chassis, Vector3.new(-trackX, below, length * 0.3)),
			makeEmitter(chassis, Vector3.new(trackX, below, length * 0.3)),
		},
	}
end

-- A truck model can stream in before its chassis does: retry until the PrimaryPart is there.
local function watchTruck(model)
	if not model:IsA("Model") then
		return
	end
	if model.PrimaryPart then
		track(model)
		return
	end
	local conn
	conn = model:GetPropertyChangedSignal("PrimaryPart"):Connect(function()
		if model.PrimaryPart then
			conn:Disconnect()
			track(model)
		end
	end)
end

local function untrack(model)
	trucks[model] = nil
end

CollectionService:GetInstanceAddedSignal("TruckModel"):Connect(watchTruck)
CollectionService:GetInstanceRemovedSignal("TruckModel"):Connect(untrack)
for _, model in CollectionService:GetTagged("TruckModel") do
	watchTruck(model)
end

local fov = BASE_FOV
local zoom = BASE_ZOOM
local driving = false

RunService.Heartbeat:Connect(function(dt)
	local camera = workspace.CurrentCamera
	local eye = camera and camera.CFrame.Position or Vector3.zero
	for model, t in trucks do
		local chassis = model.PrimaryPart
		if chassis ~= t.chassis then
			-- The chassis streamed out (and maybe back in as a new part): start over on whatever is there now.
			trucks[model] = nil
			if model.Parent then
				watchTruck(model)
			end
			continue
		end
		local rate = 0
		local speed = chassis.AssemblyLinearVelocity.Magnitude
		if speed > DUST_FROM and (chassis.Position - eye).Magnitude < DUST_RANGE then
			local hit = workspace:Raycast(chassis.Position, Vector3.new(0, -8, 0), t.params)
			local color = hit and DUST[hit.Material]
			if color then
				rate = 40 * math.clamp((speed - DUST_FROM) / (DUST_FULL - DUST_FROM), 0, 1)
				for _, emitter in t.emitters do
					emitter.Color = ColorSequence.new(color)
				end
			end
		end
		for _, emitter in t.emitters do
			emitter.Rate = rate
		end
	end

	-- The driver's camera: pull back and widen with speed, settle back when you stop or get out.
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	local truck = seat and seat.Name == "DriverSeat" and seat:FindFirstAncestorWhichIsA("Model")
	local share = 0
	if truck and truck:GetAttribute("TruckId") and truck.PrimaryPart then
		driving = true
		local top = truck:GetAttribute("MaxSpeed") or 46
		share = math.clamp(truck.PrimaryPart.AssemblyLinearVelocity.Magnitude / top, 0, 1)
	end
	if not driving or not camera then
		return
	end
	local ease = 1 - math.exp(-dt * 2.5)
	fov += (BASE_FOV + (FAST_FOV - BASE_FOV) * share - fov) * ease
	zoom += (BASE_ZOOM + (FAST_ZOOM - BASE_ZOOM) * share - zoom) * ease
	camera.FieldOfView = fov
	player.CameraMinZoomDistance = math.min(zoom, player.CameraMaxZoomDistance)
	if not truck and math.abs(fov - BASE_FOV) < 0.2 and zoom - BASE_ZOOM < 0.2 then
		-- Out of the truck and settled: hand the camera back untouched.
		camera.FieldOfView = BASE_FOV
		player.CameraMinZoomDistance = BASE_ZOOM
		driving = false
	end
end)
