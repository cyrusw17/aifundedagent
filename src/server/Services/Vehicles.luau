--!nonstrict
-- Trucks, part-built in the Rustic LT2 look until the Blender meshes land (a model named after the truck id in
-- ServerStorage.RusticProps replaces the look; collisions stay on the parts). The same builder makes the anchored
-- trucks on the dealer lot and the one you drive.
--
-- Driving is arcade style and runs on the driver's client (src/client/Truck.client.luau): a LinearVelocity sets the
-- speed along the ground and an AlignOrientation keeps the truck level and turns it. The wheels are low-friction
-- rollers that ride over the terrain. Nothing here touches the character's joints.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rustic = require(Shared.Config.Rustic)
local Trucks = require(Shared.Config.Trucks)
local TrailerDefs = require(Shared.Config.Trailers)
local Props = require(script.Parent.Props)
local Bales = require(script.Parent.Bales)

local Vehicles = {}

-- Body sizes in studs. Trucks with a bale bed override them (see SHAPES) so the bed matches the canonical spec in
-- BUILD_REGISTRY.md and the Blender mesh drops straight over the parts.
local DEFAULT_SHAPE = {
	wheel = 1.7, -- wheel radius; the wheel top stays under the 3.5 bed floor
	track = 4.4, -- wheel center distance from the middle, sideways
	deck = 3.1, -- chassis top
	cabW = 9.2,
	cabH = 7.0,
	cabD = 6.4,
	hood = 5.4,
	bedW = 10.9, -- outside width of a truck bed (10.2 inside)
	bedFloor = 3.5, -- top of the bed floor, level with the conveyor dock belt
	bedWall = 2.8,
}
local SHAPES = {
	-- Rusty Pickup: bed 14.6 long x 10.2 wide inside, 3.2 walls, floor top 3.5 (BUILD_REGISTRY.md). Bales lie
	-- lengthwise, three along and three across (3 x 4.6 = 13.8 long, 3 x 3.2 = 9.6 wide), 9 to a layer.
	rusty_pickup = {
		wheel = 1.65,
		track = 4.3,
		deck = 2.6,
		cabW = 9.0,
		cabH = 6.6,
		cabD = 6.2,
		hood = 5.0,
		bedW = 10.9,
		bedFloor = 3.5,
		bedWall = 3.2,
		bedLen = 15.3, -- outside length: 14.6 inside plus the front wall and tailgate
		bedGap = 0.4, -- between the cab and the bed
		meshSize = Vector3.new(10.9, 9.2, 27.5), -- the box the Blender mesh is stretched over
	},
	-- The other trucks keep the default body; these widths match their re-exported Blender meshes.
	farm_flatbed = { bedW = 11.4, meshW = 11.4 },
	box_truck = { bedW = 11.1, meshW = 11.1 },
	heavy_hauler = { meshW = 12.2 }, -- bed stays 10.2 inside; the mesh's extra width is fenders and racks
}

local function shapeOf(def)
	local shape = table.clone(DEFAULT_SHAPE)
	for k, v in SHAPES[def.id] or {} do
		shape[k] = v
	end
	return shape
end
local ROLLER = PhysicalProperties.new(0.7, 0, 0, 100, 1) -- wheels slide over the ground; the drive force moves them
local BED_GRIP = PhysicalProperties.new(0.7, 0.9, 0, 1, 1) -- with a bale's 1.2 grip, cargo holds through normal driving

local HITCH_Y = 2.2 -- height of every hitch ball and trailer coupler above level ground
local BALE_LONG, BALE_WIDE = 4.6, 3.2
local WALL_T = 0.35 -- bed wall thickness

local owned = {} -- player -> their truck model
local ownedTrailers = {} -- player -> their trailer model
local spawnFolder = nil -- where spawned player vehicles go (Vehicles.init)

function Vehicles.get(id)
	for _, def in Trucks do
		if def.id == id then
			return def
		end
	end
	return nil
end

-- Builds a truck standing on the ground at pivot (forward is pivot's LookVector). Every part is anchored; call
-- makeDrivable to weld it into one vehicle.
function Vehicles.build(def, pivot, parent)
	local model = Instance.new("Model")
	model.Name = def.name
	model:SetAttribute("TruckId", def.id)
	local paint = Rustic[def.paint] or Rustic.PaintRed
	local L = def.length
	local front = -L / 2
	local S = shapeOf(def)
	local WHEEL_RADIUS, TRACK, DECK, HOOD, BED_W = S.wheel, S.track, S.deck, S.hood, S.bedW
	local CAB_W, CAB_H, CAB_D = S.cabW, S.cabH, S.cabD
	model:SetAttribute("Deck", DECK)

	local function add(name, size, offset, color, material, shape, collide)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = pivot * offset
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = collide ~= false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		if shape then
			p.Shape = shape
		end
		p.Parent = model
		return p
	end
	local function box(name, size, x, y, z, color, material, collide)
		return add(name, size, CFrame.new(x, y, z), color, material, nil, collide)
	end
	local function glass(name, size, x, y, z)
		local p = box(name, size, x, y, z, Rustic.Glass, Enum.Material.Glass, false)
		p.Transparency = 0.55
		return p
	end

	-- Chassis: the root of the vehicle. Invisible underneath, so terrain bumps never snag it.
	local chassis = box("Chassis", Vector3.new(BED_W * 0.5, 0.8, L - 2), 0, DECK - 0.4, 0, Rustic.Metal, Enum.Material.Metal, false)
	model.PrimaryPart = chassis

	-- Wheels double as the rollers the truck rides on.
	local axles = { front + HOOD * 0.55, L / 2 - WHEEL_RADIUS * 2 }
	if def.style == "hauler" then
		axles = { front + HOOD * 0.55, L / 2 - WHEEL_RADIUS * 4.2, L / 2 - WHEEL_RADIUS * 1.6 }
	end
	local wheels = {}
	for _, z in axles do
		for _, side in { -1, 1 } do
			local wheel = add(
				"Wheel",
				Vector3.new(0.9, WHEEL_RADIUS * 2, WHEEL_RADIUS * 2),
				CFrame.new(side * TRACK, WHEEL_RADIUS, z),
				Rustic.Tire,
				Enum.Material.SmoothPlastic,
				Enum.PartType.Cylinder
			)
			wheel.CustomPhysicalProperties = ROLLER
			table.insert(wheels, wheel)
			add("Hub", Vector3.new(0.95, WHEEL_RADIUS * 0.8, WHEEL_RADIUS * 0.8), CFrame.new(side * (TRACK + 0.02), WHEEL_RADIUS, z), Rustic.Metal, Enum.Material.Metal, Enum.PartType.Cylinder, false)
			-- Rear wheels on a bed truck sit under the bed floor, so only the front ones get a fender.
			if z < 0 or (def.style ~= "pickup" and def.style ~= "hauler") then
				box("Fender", Vector3.new(1.2, 0.4, WHEEL_RADIUS * 2 + 0.8), side * TRACK, WHEEL_RADIUS * 2 + 0.3, z, paint, Enum.Material.Metal)
			end
		end
	end

	-- Hood, grille, lights, bumper
	local hoodW, hoodH = CAB_W - 0.8, CAB_H * 0.38
	box("Hood", Vector3.new(hoodW, hoodH, HOOD), 0, DECK + hoodH / 2, front + HOOD / 2, paint, Enum.Material.Metal)
	box("Grille", Vector3.new(hoodW - 1.8, hoodH - 0.5, 0.2), 0, DECK + hoodH / 2, front - 0.05, Rustic.Metal, Enum.Material.DiamondPlate)
	for _, side in { -1, 1 } do
		box("Headlight", Vector3.new(1.1, 0.9, 0.2), side * (hoodW / 2 - 0.7), DECK + hoodH * 0.65, front - 0.08, Rustic.PaintCream, Enum.Material.Neon, false)
	end
	box("FrontBumper", Vector3.new(CAB_W + 0.4, 0.7, 0.5), 0, DECK - 0.3, front - 0.2, Rustic.Metal, Enum.Material.Metal)

	-- The cab is hollow so you can see the driver through the glass.
	local cabFront = front + HOOD
	local cabZ = cabFront + CAB_D / 2
	local cabTop = DECK + CAB_H
	box("CabFloor", Vector3.new(CAB_W, 0.3, CAB_D), 0, DECK + 0.15, cabZ, Rustic.Metal, Enum.Material.Metal)
	box("Roof", Vector3.new(CAB_W + 0.2, 0.4, CAB_D + 0.2), 0, cabTop - 0.2, cabZ, paint, Enum.Material.Metal)
	box("BackWall", Vector3.new(CAB_W, CAB_H - 0.4, 0.3), 0, DECK + (CAB_H - 0.4) / 2, cabFront + CAB_D - 0.15, paint, Enum.Material.Metal)
	local doorH = CAB_H * 0.4
	box("Dash", Vector3.new(CAB_W, doorH - 0.4, 0.3), 0, DECK + (doorH - 0.4) / 2, cabFront + 0.15, paint, Enum.Material.Metal)
	glass("Windshield", Vector3.new(CAB_W - 0.4, CAB_H - doorH - 0.4, 0.15), 0, DECK + doorH + (CAB_H - doorH - 0.4) / 2 - 0.2, cabFront + 0.2)
	for _, side in { -1, 1 } do
		local x = side * (CAB_W / 2 - 0.15)
		box("Door", Vector3.new(0.3, doorH, CAB_D), x, DECK + doorH / 2, cabZ, paint, Enum.Material.Metal)
		glass("SideWindow", Vector3.new(0.15, CAB_H - doorH - 0.4, CAB_D - 1), x, DECK + doorH + (CAB_H - doorH - 0.4) / 2, cabZ)
		for _, z in { cabFront + 0.2, cabFront + CAB_D - 0.2 } do
			box("Pillar", Vector3.new(0.3, CAB_H - doorH - 0.4, 0.4), x, DECK + doorH + (CAB_H - doorH - 0.4) / 2, z, paint, Enum.Material.Metal)
		end
	end
	box("Bench", Vector3.new(CAB_W - 0.8, 0.6, 2.0), 0, DECK + 0.3, cabFront + CAB_D - 1.3, Rustic.Cloth, Enum.Material.Fabric, false)
	add(
		"SteeringWheel",
		Vector3.new(0.2, 1.6, 1.6),
		CFrame.new(-CAB_W * 0.22, DECK + doorH + 0.2, cabFront + 1.3) * CFrame.Angles(math.rad(-30), math.pi / 2, 0),
		Rustic.BarkDark,
		Enum.Material.SmoothPlastic,
		Enum.PartType.Cylinder,
		false
	)

	-- What sits behind the cab.
	local backStart = cabFront + CAB_D
	local backLength = L / 2 - backStart
	if S.bedLen then
		backStart += S.bedGap or 0
		backLength = S.bedLen
	end
	local backZ = backStart + backLength / 2
	if def.style == "pickup" or def.style == "hauler" then
		-- An open bed for hay bales. Bales ride loose: the grippy floor and the walls are all that hold them, so hard
		-- turns and bumps can still spill them. The floor top sits at S.bedFloor to meet the conveyor dock belt.
		local wall = def.style == "hauler" and 3 or S.bedWall
		local floorTop = math.max(S.bedFloor, DECK + 0.4)
		local floor = box("BedFloor", Vector3.new(BED_W, 0.4, backLength), 0, floorTop - 0.2, backZ, Rustic.Metal, Enum.Material.Metal)
		floor.CustomPhysicalProperties = BED_GRIP
		if floorTop - 0.4 > DECK then
			for _, side in { -1, 1 } do
				box("BedRiser", Vector3.new(0.5, floorTop - 0.4 - DECK, backLength - 0.6), side * BED_W * 0.28, (floorTop - 0.4 + DECK) / 2, backZ, Rustic.Metal, Enum.Material.Metal)
			end
		end
		for _, side in { -1, 1 } do
			local bedSide = box(
				"BedSide",
				Vector3.new(0.35, wall, backLength),
				side * (BED_W / 2 - 0.175),
				floorTop + wall / 2,
				backZ,
				def.style == "hauler" and Rustic.Wood or paint,
				def.style == "hauler" and Enum.Material.WoodPlanks or Enum.Material.Metal
			)
			bedSide.CustomPhysicalProperties = BED_GRIP
		end
		box("BedFront", Vector3.new(BED_W, wall, 0.35), 0, floorTop + wall / 2, backStart + 0.175, paint, Enum.Material.Metal)
		local tailZ = backStart + backLength - 0.175
		local tailgate = box("Tailgate", Vector3.new(BED_W, wall, 0.35), 0, floorTop + wall / 2, tailZ, paint, Enum.Material.Metal)
		tailgate.CustomPhysicalProperties = BED_GRIP
		CollectionService:AddTag(tailgate, "Tailgate") -- the conveyor dock (PR #13 Dock.luau) drops it while unloading
		-- Closed and folded-down spots, from the chassis center. Open, it lies flat behind the bed at floor level.
		model:SetAttribute("TailgateClosed", CFrame.new(0, floorTop + wall / 2 - (DECK - 0.4), tailZ))
		model:SetAttribute(
			"TailgateOpen",
			CFrame.new(0, floorTop - 0.175 - (DECK - 0.4), tailZ + 0.175 + wall / 2) * CFrame.Angles(math.pi / 2, 0, 0)
		)
		-- The cargo zone, from the chassis center (which sits DECK - 0.4 above the ground).
		model:SetAttribute("CargoOffset", CFrame.new(0, floorTop + 3 - (DECK - 0.4), backZ))
		model:SetAttribute("CargoSize", Vector3.new(BED_W - 0.7, 6, backLength - 0.7))
	elseif def.style == "flatbed" then
		local floorTop = math.max(S.bedFloor, DECK + 0.5)
		box("Flatbed", Vector3.new(BED_W, 0.5, backLength), 0, floorTop - 0.25, backZ, Rustic.Wood, Enum.Material.WoodPlanks)
		for _, side in { -1, 1 } do
			for _, z in { backStart + 0.4, backZ, L / 2 - 0.4 } do
				box("Stake", Vector3.new(0.4, 2.8, 0.4), side * (BED_W / 2 - 0.2), floorTop + 1.4, z, Rustic.WoodDark, Enum.Material.Wood)
			end
		end
	elseif def.style == "box" then
		box("CargoBox", Vector3.new(BED_W, 8.6, backLength - 0.2), 0, DECK + 4.5, backZ + 0.1, Rustic.PaintCream, Enum.Material.Metal)
		box("BoxStripe", Vector3.new(BED_W + 0.05, 1, backLength - 0.2), 0, DECK + 2.4, backZ + 0.1, paint, Enum.Material.Metal, false)
	elseif def.style == "semi" then
		box("FifthWheel", Vector3.new(4, 0.4, 4), 0, DECK + 0.2, backZ + 1, Rustic.Metal, Enum.Material.DiamondPlate)
		for _, side in { -1, 1 } do
			add("Stack", Vector3.new(7, 0.7, 0.7), CFrame.new(side * (CAB_W / 2 - 0.6), DECK + 6, backStart + 0.5) * CFrame.Angles(0, 0, math.pi / 2), Rustic.Metal, Enum.Material.Metal, Enum.PartType.Cylinder)
		end
	end
	box("RearBumper", Vector3.new(BED_W - 0.4, 0.6, 0.4), 0, DECK - 0.2, L / 2 + 0.1, Rustic.Metal, Enum.Material.Metal)
	for _, side in { -1, 1 } do
		box("Taillight", Vector3.new(0.8, 0.5, 0.1), side * (BED_W / 2 - 0.7), DECK + 0.8, L / 2 + 0.02, Color3.fromRGB(120, 40, 30), Enum.Material.Neon, false)
	end

	-- The Blender mesh, when imported, takes over the look. The parts stay for collisions.
	local top = cabTop
	if def.style == "box" then
		top = DECK + 8.8 -- the cargo box stands above the cab
	elseif def.style == "semi" then
		top = DECK + 9.5 -- exhaust stacks
	end
	local meshSize = S.meshSize or Vector3.new(S.meshW or math.max(BED_W, CAB_W), top, L + 0.6)
	local mesh = Props.make(def.id, pivot * CFrame.new(0, meshSize.Y / 2, 0), meshSize, def.meshTurn and CFrame.Angles(0, math.rad(def.meshTurn), 0))
	if mesh then
		-- The parts stay visible until this client has loaded the mesh (PropMeshes.client.luau), then hide.
		Props.weldTo(mesh, chassis, model)
	end

	-- Hitch ball behind the rear bumper. Trailers couple to it (Vehicles.hitch). It never collides, so a tight
	-- turn cannot snag the coupler on it.
	local hitchZ = L / 2 + 0.9
	box("Drawbar", Vector3.new(0.5, 0.4, 1.4), 0, HITCH_Y - 0.35, L / 2 + 0.3, Rustic.Metal, Enum.Material.Metal, false)
	add("HitchBall", Vector3.new(0.6, 0.6, 0.6), CFrame.new(0, HITCH_Y, hitchZ), Rustic.Metal, Enum.Material.Metal, Enum.PartType.Ball, false)
	model:SetAttribute("HitchOffset", CFrame.new(0, HITCH_Y - (DECK - 0.4), hitchZ)) -- from the chassis center

	model:SetAttribute("Wheels", #wheels)
	model:SetAttribute("Length", L)
	model:SetAttribute("Track", TRACK)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- streams in whole, never missing a wheel
	model.Parent = parent
	return model
end

local function yawOf(cframe)
	local look = cframe.LookVector
	return math.atan2(-look.X, -look.Z)
end

-- Welds the truck into one assembly with a driver's seat and the drive constraints. It stays anchored (by its
-- chassis) until release, so a scripted drive can move it.
function Vehicles.makeDrivable(model, owner)
	local chassis = model.PrimaryPart
	local def = Vehicles.get(model:GetAttribute("TruckId"))
	local S = shapeOf(def)
	local DECK = S.deck
	local cabFront = -def.length / 2 + S.hood

	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2, 0.5, 1.8)
	-- On top of the bench, driver's side. The chassis center is DECK - 0.4 above the ground.
	local seatX, seatZ = -S.cabW * 0.22, cabFront + S.cabD - 1.3
	seat.CFrame = chassis.CFrame * CFrame.new(seatX, DECK + 0.6 - (DECK - 0.4), seatZ)
	seat.Color = Rustic.Cloth
	seat.Material = Enum.Material.Fabric
	seat.HeadsUpDisplay = false
	seat.MaxSpeed = 0 -- the client controller does the driving
	seat.Torque = 0
	seat:SetAttribute("Truck", true)
	-- Where you stand after getting out: on the ground beside the driver's door (from the chassis center). The
	-- cab has a roof, so a plain jump out would bump it and land you straight back in the seat.
	seat:SetAttribute("ExitOffset", CFrame.new(-(S.cabW / 2 + 2.5), 3.2 - (DECK - 0.4), seatZ))
	seat.Parent = model

	-- The cab is closed, so you get in with a button by the driver's door.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DrivePrompt"
	prompt.ActionText = "Drive"
	prompt.ObjectText = owner.Name .. "'s truck"
	prompt.HoldDuration = 0
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.ClickablePrompt = true
	prompt.Enabled = false -- the drive-out scene puts the owner in the seat; it turns on once they get out
	prompt.Parent = seat
	prompt.Triggered:Connect(function(player)
		if player ~= owner or seat.Occupant or seat.Disabled then
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 and not humanoid.SeatPart then
			seat:Sit(humanoid)
		end
	end)

	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p ~= chassis then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = chassis
			weld.Part1 = p
			weld.Parent = p
			p.Anchored = false
			if p.Name ~= "Wheel" then
				p.Massless = true
			end
		end
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "DriveAttachment"
	attachment.Parent = chassis

	local hitch = Instance.new("Attachment")
	hitch.Name = "HitchAttachment"
	hitch.CFrame = model:GetAttribute("HitchOffset") or CFrame.new(0, 0, def.length / 2 + 0.9)
	hitch.Parent = chassis

	local drive = Instance.new("LinearVelocity")
	drive.Name = "Drive"
	drive.Attachment0 = attachment
	-- Speed is set in the truck's own frame: forward and sideways only. Up and down stay free, so gravity and the
	-- ground decide the height, and the truck never skids sideways.
	drive.RelativeTo = Enum.ActuatorRelativeTo.Attachment0
	drive.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	drive.PrimaryTangentAxis = Vector3.xAxis
	drive.SecondaryTangentAxis = Vector3.zAxis
	drive.PlaneVelocity = Vector2.zero
	drive.MaxForce = 30000 -- enough to pull a full bed; a heavy load still speeds up slower
	drive.Parent = chassis

	local steer = Instance.new("AlignOrientation")
	steer.Name = "Steer"
	steer.Mode = Enum.OrientationAlignmentMode.OneAttachment
	steer.Attachment0 = attachment
	steer.CFrame = CFrame.Angles(0, yawOf(chassis.CFrame), 0)
	steer.MaxTorque = 2e6
	steer.Responsiveness = 30
	steer.Parent = chassis

	model:SetAttribute("OwnerId", owner.UserId)
	model:SetAttribute("MaxSpeed", def.maxSpeed)

	-- Only the owner drives. Anyone else who sits down is put straight back on their feet.
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local humanoid = seat.Occupant
		if humanoid then
			local player = Players:GetPlayerFromCharacter(humanoid.Parent)
			if player ~= owner then
				local weld = seat:FindFirstChild("SeatWeld")
				if weld then
					weld:Destroy()
				end
			end
			prompt.Enabled = false
		else
			-- The driver got out: park where it stands. The seat rests a moment so the character, now standing
			-- beside the door (Truck.client.luau), is not pulled straight back in.
			steer.CFrame = CFrame.Angles(0, yawOf(chassis.CFrame), 0)
			drive.PlaneVelocity = Vector2.new(0, 0.001)
			drive.PlaneVelocity = Vector2.zero
			seat.Disabled = true
			task.delay(1.5, function()
				if seat.Parent then
					seat.Disabled = false
					prompt.Enabled = seat.Occupant == nil
				end
			end)
		end
	end)
	return seat
end

-- Folds the tailgate down (open = true) so loose cargo can be pushed out the back, or swings it shut.
-- Used by the conveyor dock's UNLOAD step. Safe to call on any truck; returns false if it has no tailgate.
function Vehicles.setTailgate(model, open)
	local chassis = model and model.PrimaryPart
	local tailgate = model and model:FindFirstChild("Tailgate")
	local spot = model and model:GetAttribute(open and "TailgateOpen" or "TailgateClosed")
	if not chassis or not tailgate or not spot then
		return false
	end
	-- Re-weld at the new spot: moving a welded part directly would drag the whole truck.
	local weld = tailgate:FindFirstChildOfClass("WeldConstraint")
	if weld then
		weld:Destroy()
	end
	tailgate.CFrame = chassis.CFrame * spot
	if weld then
		local new = Instance.new("WeldConstraint")
		new.Part0 = chassis
		new.Part1 = tailgate
		new.Parent = tailgate
	end
	model:SetAttribute("TailgateIsOpen", open)
	return true
end

-- Trailers -------------------------------------------------------------------------------------------------------
-- A trailer is its own physics body: a bed on real wheels that spin on hinges, so it rolls along behind the truck
-- and resists sliding sideways like a real one. A ball joint at the hitch is the only link to the truck, so it
-- swings through turns and follows the ground on its own. Bales ride loose in the bed, exactly as in a truck.

function Vehicles.getTrailer(id)
	for _, def in TrailerDefs do
		if def.id == id then
			return def
		end
	end
	return nil
end

local function trailerSize(def)
	local inside = Vector3.new(def.across * BALE_WIDE + 0.6, def.wall, def.length or def.along * BALE_LONG + 0.8)
	return inside, inside.X + WALL_T * 2, inside.Z + WALL_T * 2
end

-- Builds a trailer with its bed centered over pivot (on the ground, tongue toward pivot's LookVector). Anchored
-- until makeTrailerLive.
function Vehicles.buildTrailer(def, pivot, parent)
	local model = Instance.new("Model")
	model.Name = def.name
	model:SetAttribute("TrailerId", def.id)
	local inside, W, L = trailerSize(def)
	local floorTop = DEFAULT_SHAPE.bedFloor
	local sideColor = Rustic[def.color] or Rustic.Wood
	local sideMaterial = def.color == "Metal" and Enum.Material.Metal or Enum.Material.WoodPlanks
	local front = -L / 2

	local function box(name, size, x, y, z, color, material, collide)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = pivot * CFrame.new(x, y, z)
		p.Color = color
		p.Material = material
		p.Anchored = true
		p.CanCollide = collide ~= false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end

	-- The frame rails under the floor; the chassis between them is the trailer's root and carries its weight.
	local railX = math.min(W * 0.32, 2.4)
	local railY = floorTop - 0.4 - 0.3
	local chassis = box("TrailerChassis", Vector3.new(railX * 2, 0.6, L - 1), 0, railY, 0, Rustic.Metal, Enum.Material.Metal, false)
	chassis.Transparency = 1
	chassis.CustomPhysicalProperties = PhysicalProperties.new(1.5, 0.3, 0, 1, 1)
	model.PrimaryPart = chassis
	for _, side in { -1, 1 } do
		box("Rail", Vector3.new(0.4, 0.6, L), side * railX, railY, 0, Rustic.Metal, Enum.Material.Metal)
	end

	-- The bed: floor, sides, a front wall and a tailgate the dock can fold down (setTailgate).
	local floor = box("BedFloor", Vector3.new(W, 0.4, L), 0, floorTop - 0.2, 0, Rustic.WoodDark, Enum.Material.WoodPlanks)
	floor.CustomPhysicalProperties = BED_GRIP
	for _, side in { -1, 1 } do
		local wall = box("BedSide", Vector3.new(WALL_T, def.wall, L), side * (W / 2 - WALL_T / 2), floorTop + def.wall / 2, 0, sideColor, sideMaterial)
		wall.CustomPhysicalProperties = BED_GRIP
	end
	box("BedFront", Vector3.new(W, def.wall, WALL_T), 0, floorTop + def.wall / 2, front + WALL_T / 2, sideColor, sideMaterial)
	local tailZ = L / 2 - WALL_T / 2
	local tailgate = box("Tailgate", Vector3.new(W, def.wall, WALL_T), 0, floorTop + def.wall / 2, tailZ, sideColor, sideMaterial)
	tailgate.CustomPhysicalProperties = BED_GRIP
	CollectionService:AddTag(tailgate, "Tailgate")
	model:SetAttribute("TailgateClosed", CFrame.new(0, floorTop + def.wall / 2 - railY, tailZ))
	model:SetAttribute(
		"TailgateOpen",
		CFrame.new(0, floorTop - WALL_T / 2 - railY, L / 2 + def.wall / 2) * CFrame.Angles(math.pi / 2, 0, 0)
	)
	local zoneH = math.max(6, def.wall + 2) -- tall racks hold three layers
	model:SetAttribute("CargoOffset", CFrame.new(0, floorTop + zoneH / 2 - railY, 0))
	model:SetAttribute("CargoSize", Vector3.new(inside.X - 0.4, zoneH, inside.Z - 0.4))
	for _, side in { -1, 1 } do
		box("Reflector", Vector3.new(0.6, 0.3, 0.1), side * (W / 2 - 0.6), floorTop - 0.5, L / 2 + 0.05, Rustic.PaintRed, Enum.Material.Neon, false)
	end

	-- Wheels tucked under the bed, on hinges added by makeTrailerLive.
	local wheelX = railX + 0.35 + 0.5
	for _, dz in def.axles do
		box("Axle", Vector3.new(wheelX * 2 - 0.4, 0.3, 0.3), 0, def.wheel, dz, Rustic.Metal, Enum.Material.Metal, false)
		for _, side in { -1, 1 } do
			local wheel = box("Wheel", Vector3.new(0.9, def.wheel * 2, def.wheel * 2), side * wheelX, def.wheel, dz, Rustic.Tire, Enum.Material.SmoothPlastic)
			wheel.Shape = Enum.PartType.Cylinder
			wheel.CustomPhysicalProperties = PhysicalProperties.new(0.7, 1, 0, 1, 1)
			box("Hub", Vector3.new(0.95, def.wheel * 0.8, def.wheel * 0.8), side * (wheelX + 0.02), def.wheel, dz, Rustic.Metal, Enum.Material.Metal, false).Shape =
				Enum.PartType.Cylinder
		end
	end

	-- A-frame tongue to the coupler, and a jack foot that props the nose up when it is unhitched. Neither
	-- collides near the truck, so a sharp turn swings the trailer instead of jamming it.
	local tipZ = front - def.tongue
	local tip = Vector3.new(0, HITCH_Y, tipZ)
	for _, side in { -1, 1 } do
		local from = Vector3.new(side * railX, railY, front + 0.6)
		local beam = box("Tongue", Vector3.new(0.4, 0.4, (tip - from).Magnitude), 0, 0, 0, Rustic.Metal, Enum.Material.Metal, false)
		beam.CFrame = pivot * CFrame.lookAt((from + tip) / 2, tip)
	end
	box("Coupler", Vector3.new(0.8, 0.5, 1.0), 0, HITCH_Y + 0.1, tipZ, Rustic.Metal, Enum.Material.Metal, false)
	local jackZ = tipZ + def.tongue * 0.35
	box("JackPost", Vector3.new(0.35, HITCH_Y - 0.4, 0.35), 0.5, (HITCH_Y - 0.4) / 2 + 0.6, jackZ, Rustic.Metal, Enum.Material.Metal, false)
	box("JackFoot", Vector3.new(0.9, 0.2, 0.9), 0.5, 0.7, jackZ, Rustic.Metal, Enum.Material.Metal)
	model:SetAttribute("CouplerOffset", CFrame.new(0, HITCH_Y - railY, tipZ)) -- from the chassis center
	model:SetAttribute("Length", L + def.tongue)

	local mesh = Props.make(def.id, pivot * CFrame.new(0, (floorTop + def.wall) / 2, -def.tongue / 2), Vector3.new(W + 1.2, floorTop + def.wall, L + def.tongue))
	if mesh then
		Props.weldTo(mesh, chassis, model)
	end

	model.Parent = parent
	return model
end

local function giveTrailerTo(trailer, player)
	for _, p in trailer:GetDescendants() do
		if p:IsA("BasePart") and not p.Anchored then
			pcall(function()
				p:SetNetworkOwner(player)
			end)
		end
	end
end

-- Welds the bed into one body, puts the wheels on free hinges, adds the Hitch / Unhitch button and lets it go.
function Vehicles.makeTrailerLive(model, owner)
	local chassis = model.PrimaryPart
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") and p ~= chassis then
			if p.Name == "Wheel" then
				local axle = Instance.new("Attachment")
				axle.Name = "Axle"
				axle.CFrame = chassis.CFrame:ToObjectSpace(p.CFrame)
				axle.Parent = chassis
				local hub = Instance.new("Attachment")
				hub.Name = "Hub"
				hub.Parent = p
				local hinge = Instance.new("HingeConstraint")
				hinge.Attachment0 = axle
				hinge.Attachment1 = hub
				hinge.Parent = p
			else
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = chassis
				weld.Part1 = p
				weld.Parent = p
				p.Massless = true
			end
			p.Anchored = false
		end
	end

	local coupler = Instance.new("Attachment")
	coupler.Name = "CouplerAttachment"
	coupler.CFrame = model:GetAttribute("CouplerOffset")
	coupler.Parent = chassis
	local joint = Instance.new("BallSocketConstraint")
	joint.Name = "Hitch"
	joint.Attachment1 = coupler
	joint.Enabled = false
	joint.Parent = chassis

	model:SetAttribute("OwnerId", owner.UserId)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "HitchPrompt"
	prompt.ActionText = "Hitch"
	prompt.ObjectText = owner.Name .. "'s trailer"
	prompt.HoldDuration = 0.3
	prompt.KeyboardKeyCode = Enum.KeyCode.H
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.ClickablePrompt = true
	prompt.Parent = model:FindFirstChild("Coupler") or chassis
	prompt.Triggered:Connect(function(player)
		if player ~= owner then
			return
		end
		if model:GetAttribute("HitchedTo") then
			Vehicles.unhitch(model)
		else
			local truck = owned[player]
			local ball = truck and truck.PrimaryPart and truck.PrimaryPart:FindFirstChild("HitchAttachment")
			if not ball or (ball.WorldPosition - coupler.WorldPosition).Magnitude > 8 then
				prompt.ObjectText = "Back your truck up to it"
				task.delay(2, function()
					prompt.ObjectText = owner.Name .. "'s trailer"
				end)
				return
			end
			Vehicles.hitch(truck, model)
		end
	end)

	chassis.Anchored = false
	giveTrailerTo(model, owner)
	return model
end

-- Couples a live trailer to a truck's hitch ball. The trailer slides over so the coupler sits on the ball first.
function Vehicles.hitch(truck, trailer)
	local ball = truck.PrimaryPart and truck.PrimaryPart:FindFirstChild("HitchAttachment")
	local chassis = trailer.PrimaryPart
	local coupler = chassis and chassis:FindFirstChild("CouplerAttachment")
	local joint = chassis and chassis:FindFirstChild("Hitch")
	if not ball or not coupler or not joint then
		return false
	end
	trailer:PivotTo(CFrame.new(ball.WorldPosition - coupler.WorldPosition) * trailer:GetPivot())
	joint.Attachment0 = ball
	joint.Enabled = true
	trailer:SetAttribute("HitchedTo", truck:GetAttribute("TruckId"))
	local prompt = trailer:FindFirstChild("HitchPrompt", true)
	if prompt then
		prompt.ActionText = "Unhitch"
	end
	local owner = Players:GetPlayerByUserId(trailer:GetAttribute("OwnerId") or 0)
	if owner and not truck.PrimaryPart.Anchored then
		giveTrailerTo(trailer, owner)
	end
	return true
end

-- Drops the trailer off the hitch where it stands; its jack foot holds the nose up.
function Vehicles.unhitch(trailer)
	local joint = trailer.PrimaryPart and trailer.PrimaryPart:FindFirstChild("Hitch")
	if joint then
		joint.Enabled = false
		joint.Attachment0 = nil
	end
	trailer:SetAttribute("HitchedTo", nil)
	local prompt = trailer:FindFirstChild("HitchPrompt", true)
	if prompt then
		prompt.ActionText = "Hitch"
	end
end

-- The player's trailer in the world, or nil.
function Vehicles.trailerOf(player)
	return ownedTrailers[player]
end

-- One trailer per player in the world. A new one replaces the old.
function Vehicles.setOwnedTrailer(player, model)
	local old = ownedTrailers[player]
	if old and old ~= model then
		old:Destroy()
	end
	ownedTrailers[player] = model
end

-- The player's truck in the world, or nil.
function Vehicles.ownedBy(player)
	return owned[player]
end

-- Every player truck in the world (truck model -> owner), e.g. for the dock to find the one backed up to it.
function Vehicles.all()
	local list = {}
	for player, model in owned do
		if model.Parent then
			list[model] = player
		end
	end
	for player, model in ownedTrailers do
		if model.Parent then
			list[model] = player
		end
	end
	return list
end

-- Moves an anchored truck (used by the garage drive-out).
function Vehicles.place(model, cframe)
	local chassis = model.PrimaryPart
	chassis.CFrame = cframe * CFrame.new(0, model:GetAttribute("Deck") - 0.4, 0)
end

function Vehicles.groundCFrame(model)
	return model.PrimaryPart.CFrame * CFrame.new(0, -(model:GetAttribute("Deck") - 0.4), 0)
end

-- Hands the truck to physics and to its owner's client.
function Vehicles.release(model, owner)
	local chassis = model.PrimaryPart
	chassis.Steer.CFrame = CFrame.Angles(0, yawOf(chassis.CFrame), 0)
	chassis.Anchored = false
	pcall(function()
		chassis:SetNetworkOwner(owner)
	end)
	local trailer = ownedTrailers[owner]
	if trailer and trailer:GetAttribute("HitchedTo") == model:GetAttribute("TruckId") then
		giveTrailerTo(trailer, owner)
	end
end

-- One truck per player in the world. A new one replaces the old.
function Vehicles.setOwned(player, model)
	local old = owned[player]
	if old and old ~= model then
		old:Destroy()
	end
	owned[player] = model
end

-- Bales in a truck bed ride loose, so they must be simulated by the same computer as the truck (its driver's).
-- Otherwise the server and the driver disagree about where the bed is and the load slides off. This hands every
-- bale in a bed to the truck's owner, marks it so it does not despawn, and gives it back to the server once it
-- falls or is lifted out.
local riding = {} -- bale record -> true

local function updateCargo()
	local now = {}
	for model, player in Vehicles.all() do
		local chassis = model.PrimaryPart
		local offset, size = model:GetAttribute("CargoOffset"), model:GetAttribute("CargoSize")
		-- While the dock unloads (tailgate open), the dock owns the cargo's physics; leave it alone.
		if not chassis or not offset or chassis.Anchored or model:GetAttribute("TailgateIsOpen") then
			continue
		end
		for _, p in workspace:GetPartBoundsInBox(chassis.CFrame * offset, size) do
			local b = Bales.fromPart(p)
			if b and not b.gone and not b.carriedBy and not b.breaking and not now[b] and not b.body.Anchored then
				now[b] = true
				if not riding[b] then
					b.body:SetAttribute("InTruck", true)
				end
				-- Whoever hauls a bale gets paid for it at the sell shop, even if it was pushed in rather than carried.
				b.ownerId = b.ownerId or player.UserId
				pcall(function()
					if b.body:GetNetworkOwner() ~= player then
						b.body:SetNetworkOwner(player)
					end
				end)
			end
		end
	end
	for b in riding do
		if not now[b] and not b.gone then
			b.body:SetAttribute("InTruck", nil)
			if not b.carriedBy then
				pcall(function()
					b.body:SetNetworkOwner(nil)
				end)
			end
		end
	end
	riding = now
end

-- Puts a player's truck in the world ready to drive, parked at cframe (a spot on the ground; the truck faces its
-- LookVector), with their trailer hitched behind it when opts.trailer names one. Replaces any truck and trailer they
-- already had out. Used for saves that already own vehicles, e.g. by the land plots when a save loads:
--   Vehicles.spawnOwned(player, "rusty_pickup", plotSpot, { trailer = "small_trailer" })
-- Returns the truck and the trailer (or nil).
function Vehicles.spawnOwned(player, truckId, cframe, opts)
	opts = opts or {}
	local def = Vehicles.get(truckId)
	assert(def, "unknown truck " .. tostring(truckId))
	local parent = opts.parent or spawnFolder or workspace
	local truck = Vehicles.build(def, cframe, parent)
	truck.Name = player.Name .. "'s " .. def.name
	Vehicles.makeDrivable(truck, player)
	Vehicles.setOwned(player, truck)

	local trailer = opts.trailer and Vehicles.spawnTrailer(opts.trailer, truck)

	Vehicles.release(truck, player)
	local seat = truck:FindFirstChild("DriverSeat")
	local prompt = seat and seat:FindFirstChild("DrivePrompt")
	if prompt then
		prompt.Enabled = true -- nobody is in it yet
	end
	return truck, trailer
end

-- Builds the truck owner's trailer behind a truck that is already in the world and hitches it. Returns the trailer.
-- (For callers that place the truck themselves; spawnOwned does both.)
function Vehicles.spawnTrailer(trailerId, truck)
	local def = Vehicles.getTrailer(trailerId)
	local owner = Players:GetPlayerByUserId(truck:GetAttribute("OwnerId") or 0)
	local truckDef = Vehicles.get(truck:GetAttribute("TruckId"))
	if not def or not owner or not truckDef then
		warn("[Needlewood] spawnTrailer: unknown trailer or truck owner " .. tostring(trailerId))
		return nil
	end
	local _, _, bedLength = trailerSize(def)
	local behind = truckDef.length / 2 + 0.9 + def.tongue + bedLength / 2
	local trailer = Vehicles.buildTrailer(def, Vehicles.groundCFrame(truck) * CFrame.new(0, 0, behind), truck.Parent)
	trailer.Name = owner.Name .. "'s " .. def.name
	Vehicles.makeTrailerLive(trailer, owner)
	Vehicles.setOwnedTrailer(owner, trailer)
	Vehicles.hitch(truck, trailer)
	return trailer
end

-- folder: where player trucks and trailers go.
function Vehicles.init(folder)
	spawnFolder = folder
	Players.PlayerRemoving:Connect(function(player)
		if owned[player] then
			owned[player]:Destroy()
			owned[player] = nil
		end
		if ownedTrailers[player] then
			ownedTrailers[player]:Destroy()
			ownedTrailers[player] = nil
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.3)
			updateCargo()
		end
	end)
end

return Vehicles
