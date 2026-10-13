--!nonstrict
-- Makes conveyor belts look like they move: light slats slide along each belt at its speed.
-- Only visual and only on this client. The server's belt velocity is what actually carries loads.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local SLATS = 3
local SLAT_COLOR = Color3.fromRGB(77, 64, 51)

local belts = {} -- belt part -> its slats

local function add(belt)
	if belts[belt] or not belt:IsA("BasePart") then
		return
	end
	local slats = {}
	for _ = 1, SLATS do
		local slat = Instance.new("Part")
		slat.Name = "BeltSlat"
		slat.Anchored = true
		slat.CanCollide = false
		slat.CanQuery = false
		slat.CanTouch = false
		slat.CastShadow = false
		slat.Size = Vector3.new(belt.Size.X - 0.8, 0.06, 0.35)
		slat.Color = SLAT_COLOR
		slat.Material = Enum.Material.SmoothPlastic
		slat.Parent = belt
		table.insert(slats, slat)
	end
	belts[belt] = slats
end

local function remove(belt)
	local slats = belts[belt]
	if slats then
		for _, slat in slats do
			slat:Destroy()
		end
		belts[belt] = nil
	end
end

CollectionService:GetInstanceAddedSignal("ConveyorBelt"):Connect(add)
CollectionService:GetInstanceRemovedSignal("ConveyorBelt"):Connect(remove)
for _, belt in CollectionService:GetTagged("ConveyorBelt") do
	add(belt)
end

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	for belt, slats in belts do
		if not belt.Parent then
			remove(belt)
			continue
		end
		local length = belt.Size.Z
		local spacing = length / SLATS
		local travelled = now * (belt:GetAttribute("Speed") or 0)
		for i, slat in slats do
			local along = (travelled + i * spacing) % length
			-- Forward is the belt's -Z, so slats enter at +Z and leave at -Z.
			slat.CFrame = belt.CFrame * CFrame.new(0, belt.Size.Y / 2 + 0.03, length / 2 - along)
		end
	end
end)

-- The moving pieces of Blender machine meshes (Skins.luau): rollers, drums, reels and flywheels spin about their axle,
-- shaker beds rattle. A piece inside a model with a "Running" attribute only moves while it is true.
local SPIN_SPEED = 6 -- radians per second
local SHAKE = 0.12 -- studs

local moving = {} -- part -> { rest = CFrame, axis = Vector3, kind = string, machine = Instance? }

-- A cylinder's axle is the side whose length differs most from the other two.
local function axle(size)
	local x, y, z = size.X, size.Y, size.Z
	local dx = math.abs(x - y) + math.abs(x - z)
	local dy = math.abs(y - x) + math.abs(y - z)
	local dz = math.abs(z - x) + math.abs(z - y)
	if dx >= dy and dx >= dz then
		return Vector3.xAxis
	end
	return dy >= dz and Vector3.yAxis or Vector3.zAxis
end

local function addMoving(part)
	if moving[part] or not part:IsA("BasePart") then
		return
	end
	local machine = part.Parent
	while machine and machine:GetAttribute("Running") == nil and machine ~= workspace do
		machine = machine.Parent
	end
	moving[part] = {
		rest = part.CFrame,
		-- an "Axis" attribute (a Vector3, in the part's own space) overrides the guess, as a windmill sail needs: its
		-- long side is not its axle
		axis = typeof(part:GetAttribute("Axis")) == "Vector3" and part:GetAttribute("Axis") or axle(part.Size),
		kind = part:GetAttribute("Motion") or "Spin",
		machine = machine ~= workspace and machine or nil,
	}
end

CollectionService:GetInstanceAddedSignal("PropMotion"):Connect(addMoving)
CollectionService:GetInstanceRemovedSignal("PropMotion"):Connect(function(part)
	moving[part] = nil
end)
for _, part in CollectionService:GetTagged("PropMotion") do
	addMoving(part)
end

local spun = 0
RunService.RenderStepped:Connect(function(dt)
	spun += dt * SPIN_SPEED
	for part, m in moving do
		if not part.Parent then
			moving[part] = nil
			continue
		end
		if m.machine and not m.machine:GetAttribute("Running") then
			part.CFrame = m.rest
		elseif m.kind == "Shake" then
			part.CFrame = m.rest * CFrame.new(math.sin(spun * 5) * SHAKE, 0, math.cos(spun * 3.7) * SHAKE * 0.5)
		else
			part.CFrame = m.rest * CFrame.fromAxisAngle(m.axis, spun)
		end
	end
end)
