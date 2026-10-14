--!nonstrict
-- Life around the map, drawn only on this client so it costs the server nothing: windmill sails turning (the
-- windmills are tagged "WindmillSails" by Regions.luau) and small flocks of birds wheeling overhead in the daytime.
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local SAIL_SPEED = 0.6 -- radians a second
local SAIL_RANGE = 700 -- sails further away than this stand still
local FLOCKS = 2
local BIRDS = 6
local BIRD_COLOR = Color3.fromRGB(52, 48, 44)

-- Windmills -------------------------------------------------------------------------------------------------------

local sails = {} -- model -> { pivot = its starting CFrame, angle }

local function addSails(model)
	if model:IsA("Model") and model.PrimaryPart then
		sails[model] = { pivot = model:GetPivot(), angle = 0 }
	end
end
for _, model in CollectionService:GetTagged("WindmillSails") do
	addSails(model)
end
CollectionService:GetInstanceAddedSignal("WindmillSails"):Connect(addSails)
CollectionService:GetInstanceRemovedSignal("WindmillSails"):Connect(function(model)
	sails[model] = nil
end)

-- Birds -----------------------------------------------------------------------------------------------------------

local birdFolder = Instance.new("Folder")
birdFolder.Name = "AmbientBirds"
birdFolder.Parent = Workspace.CurrentCamera

local function wing(parent)
	local p = Instance.new("Part")
	p.Size = Vector3.new(1.4, 0.12, 0.5)
	p.Color = BIRD_COLOR
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

local flocks = {}
for f = 1, FLOCKS do
	local flock = { center = nil, radius = 30 + f * 12, height = 60 + f * 14, phase = f * 2.1, birds = {} }
	for b = 1, BIRDS do
		table.insert(flock.birds, {
			left = wing(birdFolder),
			right = wing(birdFolder),
			offset = Vector3.new(math.random(-8, 8), math.random(-4, 4), math.random(-8, 8)),
			flap = math.random() * 6,
		})
	end
	table.insert(flocks, flock)
end

local function setBirdsVisible(visible)
	local parent = visible and Workspace.CurrentCamera or nil
	if birdFolder.Parent ~= parent then
		birdFolder.Parent = parent
	end
end

local clock = 0
RunService.RenderStepped:Connect(function(dt)
	clock += dt
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local here = root.Position

	for model, s in sails do
		if model.Parent and (s.pivot.Position - here).Magnitude < SAIL_RANGE then
			s.angle = (s.angle + SAIL_SPEED * dt) % (math.pi * 2)
			-- The hub's long axis (its X) is the sails' axle.
			local turn = CFrame.fromAxisAngle(s.pivot.RightVector, s.angle)
			model:PivotTo(CFrame.new(s.pivot.Position) * turn * s.pivot.Rotation)
		end
	end

	local day = Lighting.ClockTime > 6 and Lighting.ClockTime < 18.5
	setBirdsVisible(day)
	if not day then
		return
	end
	for _, flock in flocks do
		-- Each flock drifts after the player, slowly, so it is always somewhere overhead but never glued on.
		local target = here + Vector3.new(math.cos(flock.phase) * 90, 0, math.sin(flock.phase) * 90)
		flock.center = flock.center and flock.center:Lerp(target, math.min(1, dt * 0.05)) or target
		local a = clock * 0.25 + flock.phase
		local lead = flock.center + Vector3.new(math.cos(a) * flock.radius, flock.height + math.sin(clock * 0.4) * 6, math.sin(a) * flock.radius)
		local heading = Vector3.new(-math.sin(a), 0, math.cos(a))
		for _, bird in flock.birds do
			local pos = lead + bird.offset
			local body = CFrame.lookAt(pos, pos + heading)
			local beat = math.sin(clock * 9 + bird.flap) * 0.6
			bird.left.CFrame = body * CFrame.Angles(0, 0, beat) * CFrame.new(-0.7, 0, 0)
			bird.right.CFrame = body * CFrame.Angles(0, 0, -beat) * CFrame.new(0.7, 0, 0)
		end
	end
end)
