--!nonstrict
-- The hay trailer. A truck pulls a long trailer stacked with bales up the road, then backs it up to the loading
-- dock at the start of the conveyor line. On unload, the trailer's walking floor slides the whole load out the back
-- onto the belt. Then the truck drives off. One trailer at a time.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Factory = require(ReplicatedStorage.Shared.Config.Factory)
local Bales = require(script.Parent.Bales)

local Trailer = {}

local BED_LENGTH = 24
local BED_WIDTH = 6
local BED_TOP = Factory.BeltTop + 0.5 -- a little above the belt, so bales drop onto it
local BALE_LONG, BALE_HIGH = 4.6, 2.6 -- Bales.luau size, turned to lie along the trailer

-- Rustic palette (blender/lib/style.py): weathered planks, rusty steel, dark bark-brown tires.
local SIDES = Color3.fromRGB(179, 153, 115)
local PLANKS = Color3.fromRGB(133, 110, 82)
local IRON = Color3.fromRGB(102, 66, 42)
local TIRE = Color3.fromRGB(41, 33, 26)
local CAB = Color3.fromRGB(107, 94, 84)
local GLASS = Color3.fromRGB(41, 33, 26)
local CREAM = Color3.fromRGB(128, 117, 105)

local SLICK = PhysicalProperties.new(0.7, 0, 0, 100, 1)
local GRIP = PhysicalProperties.new(0.7, 1.2, 0, 100, 1)

local parentFolder = nil
local path = nil -- start, turn, bend and dock CFrames worked out from the dock
local current = nil -- the trailer in the world right now, or nil

Trailer.state = "none" -- none, arriving, parked, unloading, leaving
Trailer.changed = Instance.new("BindableEvent")

local function setState(state)
	Trailer.state = state
	Trailer.changed:Fire(state)
end

local function part(rig, name, size, offset, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p:SetAttribute("Offset", offset)
	p.Parent = rig.model
	table.insert(rig.parts, p)
	return p
end

-- Builds the truck and trailer around a pivot at the middle of the trailer's back edge, level with the bed.
-- Forward is the pivot's LookVector, so the trailer runs from the pivot forward and the cab sits in front.
local function buildRig(pivot)
	local rig = { model = Instance.new("Model"), parts = {}, bales = {} }
	rig.model.Name = "HayTrailer"

	local wheelY = -BED_TOP + 1.4
	rig.bed = part(rig, "Bed", Vector3.new(BED_WIDTH, 0.6, BED_LENGTH), CFrame.new(0, -0.3, -BED_LENGTH / 2), PLANKS, Enum.Material.WoodPlanks)
	rig.bed.CustomPhysicalProperties = GRIP
	for _, sx in { -1, 1 } do
		local wall = part(rig, "Wall", Vector3.new(0.3, 2.4, BED_LENGTH), CFrame.new(sx * 2.85, 1.2, -BED_LENGTH / 2), SIDES, Enum.Material.WoodPlanks)
		wall.CustomPhysicalProperties = SLICK
		part(rig, "Chassis", Vector3.new(0.8, 1, BED_LENGTH), CFrame.new(sx * 2, -1.1, -BED_LENGTH / 2), IRON, Enum.Material.CorrodedMetal)
		for _, z in { -3, -6.2, -27, -31.5 } do
			part(
				rig,
				"Wheel",
				Vector3.new(0.8, 2.8, 2.8),
				CFrame.new(sx * 2.6, wheelY, z),
				TIRE,
				Enum.Material.SmoothPlastic,
				Enum.PartType.Cylinder
			)
		end
	end
	part(rig, "FrontWall", Vector3.new(BED_WIDTH, 2.4, 0.3), CFrame.new(0, 1.2, -BED_LENGTH + 0.15), SIDES, Enum.Material.WoodPlanks)
	part(rig, "Hitch", Vector3.new(1, 0.6, 2), CFrame.new(0, -1.1, -BED_LENGTH - 1), IRON, Enum.Material.CorrodedMetal)

	-- The truck: chassis, cab with a dark windshield, and a hood.
	part(rig, "TruckChassis", Vector3.new(5, 1, 9), CFrame.new(0, -1.6, -29.5), IRON, Enum.Material.CorrodedMetal)
	part(rig, "Cab", Vector3.new(5.6, 4.6, 4.4), CFrame.new(0, 1.2, -28.4), CAB, Enum.Material.Metal)
	part(rig, "Windshield", Vector3.new(4.8, 1.8, 0.2), CFrame.new(0, 2.2, -30.65), GLASS)
	part(rig, "Hood", Vector3.new(5.2, 2.2, 3.4), CFrame.new(0, -0.1, -32.3), CAB, Enum.Material.Metal)
	part(rig, "Grille", Vector3.new(4, 1.4, 0.2), CFrame.new(0, -0.1, -34.05), CREAM, Enum.Material.Metal)

	local root = part(rig, "Pivot", Vector3.new(1, 1, 1), CFrame.new(), CREAM)
	root.Transparency = 1
	root.CanCollide = false
	root.CanQuery = false
	rig.model.PrimaryPart = root

	for _, p in rig.parts do
		p.CFrame = pivot * p:GetAttribute("Offset")
	end
	rig.model.Parent = parentFolder
	return rig
end

-- Stacks two layers of bales on the bed, long side along the trailer, welded down so they ride along.
local function loadBales(rig, ownerId)
	local perLayer = math.ceil(Factory.TrailerBales / 2)
	local turn = CFrame.Angles(0, math.pi / 2, 0)
	for i = 0, Factory.TrailerBales - 1 do
		local layer = i // perLayer
		local slot = i % perLayer
		local offset = CFrame.new(0, BALE_HIGH / 2 + layer * (BALE_HIGH + 0.02), -(0.2 + BALE_LONG / 2 + slot * (BALE_LONG + 0.05)))
		local b = Bales.spawn(Vector3.zero, false, false)
		b.ownerId = ownerId
		b.prompt.Enabled = false -- no lifting bales off a moving trailer
		b.body.CFrame = rig.model.PrimaryPart.CFrame * offset * turn
		b.body.Anchored = false
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = rig.bed
		weld.Part1 = b.body
		weld.Parent = b.body
		b.trailerWeld = weld
		table.insert(rig.bales, b)
	end
end

-- Moves the rig along a path. at(alpha) gives the pivot CFrame for alpha 0..1.
local function drive(rig, seconds, at)
	local started = os.clock()
	while rig.model.Parent do
		local alpha = math.min((os.clock() - started) / seconds, 1)
		rig.model:PivotTo(at(alpha))
		if alpha >= 1 then
			break
		end
		RunService.Heartbeat:Wait()
	end
end

local function bezier(a, b, c, t)
	local u = 1 - t
	return u * u * a + 2 * u * t * b + t * t * c
end

-- dockPoint is the ground point at the back edge of the dock tile. out points from the belt toward where the
-- trailer parks. side is the way the truck faces as it pulls past before backing in.
function Trailer.init(folder, dockPoint, out, side)
	parentFolder = folder
	local up = Vector3.new(0, BED_TOP, 0)
	local dock = dockPoint + up + out * 0.2
	local bend = dock + out * 30
	local turn = bend + side * 30
	local start = turn - side * 200
	path = { dock = dock, bend = bend, turn = turn, start = start, out = out, side = side }

	-- A dirt road the truck drives in on, and the apron it backs across.
	local function road(name, from, to, width)
		local mid = (from + to) / 2
		local length = (to - from).Magnitude + width
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanQuery = false
		p.Size = Vector3.new(width, 0.1, length)
		p.CFrame = CFrame.lookAt(Vector3.new(mid.X, 0.05, mid.Z), Vector3.new(to.X, 0.05, to.Z))
		p.Color = Color3.fromRGB(196, 170, 118)
		p.Material = Enum.Material.Ground
		p.TopSurface = Enum.SurfaceType.Smooth
		p.Parent = folder
	end
	road("Road", start, turn, 10)
	road("DockApron", dock, bend, 10)
	road("TurnPad", bend, turn, 10)
end

-- Calls a trailer full of bales for this player. Returns false and a reason if one is already here.
function Trailer.order(player)
	if current then
		return false, "A trailer is already at the base."
	end
	local rig = buildRig(CFrame.lookAt(path.start, path.start + path.side))
	current = rig
	loadBales(rig, player.UserId)
	setState("arriving")

	task.spawn(function()
		-- Drive up the road, nose first.
		local forward = path.turn - path.start
		drive(rig, forward.Magnitude / Factory.TrailerDriveSpeed, function(alpha)
			local at = path.start + forward * alpha
			return CFrame.lookAt(at, at + path.side)
		end)
		task.wait(0.4)
		-- Back up in a curve until the trailer's open end meets the dock.
		local arc = (path.turn - path.bend).Magnitude + (path.bend - path.dock).Magnitude
		drive(rig, arc / Factory.TrailerReverseSpeed, function(alpha)
			local t = alpha * alpha * (3 - 2 * alpha) -- ease in and out
			local at = bezier(path.turn, path.bend, path.dock, t)
			local moving = 2 * (1 - t) * (path.bend - path.turn) + 2 * t * (path.dock - path.bend)
			local facing = moving.Magnitude > 0.01 and -moving.Unit or path.out
			return CFrame.lookAt(at, at + facing)
		end)
		setState("parked")
	end)
	return true
end

local function despawnLater(b)
	local token = b.dropToken
	task.delay(Factory.LooseBaleSeconds, function()
		if not b.gone and not b.carriedBy and b.dropToken == token and not Bales.isAtDropOff(b) then
			Bales.consume(b)
		end
	end)
end

-- Starts the walking floor: the bed slides everything out the open back onto the belt.
function Trailer.unload()
	if not current or Trailer.state ~= "parked" then
		return false
	end
	local rig = current
	setState("unloading")
	for _, b in rig.bales do
		if b.trailerWeld then
			b.trailerWeld:Destroy()
			b.trailerWeld = nil
		end
		if not b.gone then
			pcall(function()
				b.body:SetNetworkOwner(nil)
			end)
			b.prompt.Enabled = true
			despawnLater(b)
		end
	end
	rig.bed.AssemblyLinearVelocity = -rig.model.PrimaryPart.CFrame.LookVector * Factory.WalkingFloorSpeed

	task.spawn(function()
		-- Wait until the bed is empty (or give up after a while so a stuck bale cannot hold the dock forever).
		local started = os.clock()
		while os.clock() - started < 30 do
			task.wait(0.5)
			local onBed = false
			local bedCenter = rig.bed.Position
			for _, b in rig.bales do
				if not b.gone and not b.carriedBy then
					local flat = b.body.Position - bedCenter
					if math.abs(rig.bed.CFrame:VectorToObjectSpace(flat).Z) < BED_LENGTH / 2 and math.abs(flat.Y) < 8 then
						onBed = true
					end
				end
			end
			if not onBed then
				break
			end
		end
		rig.bed.AssemblyLinearVelocity = Vector3.zero
		task.wait(1)

		setState("leaving")
		local from = rig.model:GetPivot()
		drive(rig, 1.5, function(alpha)
			return from + path.out * (alpha * alpha * 18)
		end)
		local fade = TweenInfo.new(0.8)
		for _, p in rig.parts do
			if p.Transparency < 1 then
				TweenService:Create(p, fade, { Transparency = 1 }):Play()
			end
		end
		task.wait(0.9)
		rig.model:Destroy()
		current = nil
		setState("none")
	end)
	return true
end

return Trailer
