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

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rustic = require(Shared.Config.Rustic)
local Trucks = require(Shared.Config.Trucks)
local Props = require(script.Parent.Props)
local Bales = require(script.Parent.Bales)

local Vehicles = {}

local WHEEL_RADIUS = 1.4
local TRACK = 2.6 -- wheel center distance from the middle, sideways
local DECK = 2.2 -- chassis top
local CAB_W, CAB_H, CAB_D = 5.6, 5.4, 4.8
local HOOD = 3.6
local BED_W = 6.2 -- outside width of a truck bed
local ROLLER = PhysicalProperties.new(0.7, 0, 0, 100, 1) -- wheels slide over the ground; the drive force moves them
local BED_GRIP = PhysicalProperties.new(0.7, 0.9, 0, 1, 1) -- with a bale's 1.2 grip, cargo holds through normal driving

local owned = {} -- player -> their truck model

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
	local body = {} -- parts whose look the Blender mesh replaces

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
		table.insert(body, p)
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
	local chassis = box("Chassis", Vector3.new(4.2, 0.8, L - 2), 0, DECK - 0.4, 0, Rustic.Rust, Enum.Material.CorrodedMetal, false)
	model.PrimaryPart = chassis

	-- Wheels double as the rollers the truck rides on.
	local axles = { front + 2.8, L / 2 - 2.6 }
	if def.style == "hauler" then
		axles = { front + 2.8, L / 2 - 5.4, L / 2 - 2.4 }
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
			add("Hub", Vector3.new(0.95, 1.1, 1.1), CFrame.new(side * (TRACK + 0.02), WHEEL_RADIUS, z), Rustic.Metal, Enum.Material.Metal, Enum.PartType.Cylinder, false)
			box("Fender", Vector3.new(1.2, 0.4, WHEEL_RADIUS * 2 + 0.8), side * TRACK, DECK + 0.7, z, paint, Enum.Material.Metal)
		end
	end

	-- Hood, grille, lights, bumper
	box("Hood", Vector3.new(5.2, 1.8, HOOD), 0, DECK + 0.9, front + HOOD / 2, paint, Enum.Material.Metal)
	box("Grille", Vector3.new(4.2, 1.3, 0.2), 0, DECK + 0.8, front - 0.05, Rustic.Metal, Enum.Material.DiamondPlate)
	for _, side in { -1, 1 } do
		box("Headlight", Vector3.new(0.9, 0.7, 0.2), side * 1.9, DECK + 1.25, front - 0.08, Rustic.PaintCream, Enum.Material.Neon, false)
	end
	box("FrontBumper", Vector3.new(5.8, 0.6, 0.5), 0, DECK - 0.3, front - 0.2, Rustic.Rust, Enum.Material.CorrodedMetal)

	-- The cab is hollow so you can see the driver through the glass.
	local cabFront = front + HOOD
	local cabZ = cabFront + CAB_D / 2
	local cabTop = DECK + CAB_H
	box("CabFloor", Vector3.new(CAB_W, 0.3, CAB_D), 0, DECK + 0.15, cabZ, Rustic.Metal, Enum.Material.Metal)
	box("Roof", Vector3.new(CAB_W + 0.2, 0.4, CAB_D + 0.2), 0, cabTop - 0.2, cabZ, paint, Enum.Material.Metal)
	box("BackWall", Vector3.new(CAB_W, CAB_H - 0.4, 0.3), 0, DECK + (CAB_H - 0.4) / 2, cabFront + CAB_D - 0.15, paint, Enum.Material.Metal)
	box("Dash", Vector3.new(CAB_W, 1.6, 0.3), 0, DECK + 0.8, cabFront + 0.15, paint, Enum.Material.Metal)
	glass("Windshield", Vector3.new(CAB_W - 0.4, CAB_H - 2.0, 0.15), 0, DECK + 1.6 + (CAB_H - 2.0) / 2, cabFront + 0.2)
	for _, side in { -1, 1 } do
		local x = side * (CAB_W / 2 - 0.15)
		box("Door", Vector3.new(0.3, 2.0, CAB_D), x, DECK + 1.0, cabZ, paint, Enum.Material.Metal)
		glass("SideWindow", Vector3.new(0.15, CAB_H - 2.4, CAB_D - 1), x, DECK + 2.0 + (CAB_H - 2.4) / 2, cabZ)
		for _, z in { cabFront + 0.2, cabFront + CAB_D - 0.2 } do
			box("Pillar", Vector3.new(0.3, CAB_H - 2.4, 0.4), x, DECK + 2.0 + (CAB_H - 2.4) / 2, z, paint, Enum.Material.Metal)
		end
		if def.id == "rusty_pickup" then
			box("RustPatch", Vector3.new(0.34, 0.8, 1.3), x, DECK + 0.6, cabZ + side * 0.8, Rustic.Rust, Enum.Material.CorrodedMetal, false)
		end
	end
	box("Bench", Vector3.new(CAB_W - 0.8, 0.6, 1.6), 0, DECK + 0.6, cabFront + CAB_D - 1.1, Rustic.Cloth, Enum.Material.Fabric, false)
	add(
		"SteeringWheel",
		Vector3.new(0.2, 1.4, 1.4),
		CFrame.new(-1.2, DECK + 1.9, cabFront + 0.9) * CFrame.Angles(math.rad(-30), math.pi / 2, 0),
		Rustic.BarkDark,
		Enum.Material.SmoothPlastic,
		Enum.PartType.Cylinder,
		false
	)

	-- What sits behind the cab.
	local backStart = cabFront + CAB_D
	local backLength = L / 2 - backStart
	local backZ = backStart + backLength / 2
	if def.style == "pickup" or def.style == "hauler" then
		-- An open bed sized for hay bales: 5.6 studs inside, so a 4.6 stud bale fits crosswise, two to a layer.
		-- Bales ride loose. The grippy floor is all that holds them, so hard turns and bumps can still spill them.
		local wall = def.style == "hauler" and 3 or 1.6
		local floor = box("BedFloor", Vector3.new(BED_W, 0.4, backLength), 0, DECK + 0.2, backZ, Rustic.Wood, Enum.Material.WoodPlanks)
		floor.CustomPhysicalProperties = BED_GRIP
		for _, side in { -1, 1 } do
			local bedSide = box(
				"BedSide",
				Vector3.new(0.3, wall, backLength),
				side * (BED_W / 2 - 0.15),
				DECK + 0.4 + wall / 2,
				backZ,
				def.style == "hauler" and Rustic.Wood or paint,
				def.style == "hauler" and Enum.Material.WoodPlanks or Enum.Material.Metal
			)
			bedSide.CustomPhysicalProperties = BED_GRIP
		end
		box("Tailgate", Vector3.new(BED_W, wall, 0.3), 0, DECK + 0.4 + wall / 2, L / 2 - 0.15, paint, Enum.Material.Metal)
		model:SetAttribute("CargoOffset", CFrame.new(0, 0.4 + 0.4 + 3, backZ - 0.15)) -- from the chassis center
		model:SetAttribute("CargoSize", Vector3.new(BED_W - 0.6, 6, backLength - 0.3))
	elseif def.style == "flatbed" then
		box("Flatbed", Vector3.new(6, 0.5, backLength), 0, DECK + 0.25, backZ, Rustic.Wood, Enum.Material.WoodPlanks)
		for _, side in { -1, 1 } do
			for _, z in { backStart + 0.4, L / 2 - 0.4 } do
				box("Stake", Vector3.new(0.4, 2.2, 0.4), side * 2.8, DECK + 1.6, z, Rustic.WoodDark, Enum.Material.Wood)
			end
		end
	elseif def.style == "box" then
		box("CargoBox", Vector3.new(6, 6.2, backLength - 0.2), 0, DECK + 3.3, backZ + 0.1, Rustic.PaintCream, Enum.Material.Metal)
		box("BoxStripe", Vector3.new(6.05, 0.8, backLength - 0.2), 0, DECK + 2.0, backZ + 0.1, paint, Enum.Material.Metal, false)
	elseif def.style == "semi" then
		box("FifthWheel", Vector3.new(3, 0.4, 3), 0, DECK + 0.2, backZ + 1, Rustic.Metal, Enum.Material.DiamondPlate)
		for _, side in { -1, 1 } do
			add("Stack", Vector3.new(5, 0.6, 0.6), CFrame.new(side * 2.2, DECK + 4.5, backStart + 0.5) * CFrame.Angles(0, 0, math.pi / 2), Rustic.Metal, Enum.Material.Metal, Enum.PartType.Cylinder)
		end
	end
	box("RearBumper", Vector3.new(5.8, 0.5, 0.4), 0, DECK - 0.2, L / 2 + 0.1, Rustic.Rust, Enum.Material.CorrodedMetal)
	for _, side in { -1, 1 } do
		box("Taillight", Vector3.new(0.6, 0.4, 0.1), side * 2.4, DECK + 0.8, L / 2 + 0.02, Color3.fromRGB(120, 40, 30), Enum.Material.Neon, false)
	end

	-- The Blender mesh, when imported, takes over the look. The parts stay for collisions.
	local mesh = Props.make(def.id, pivot * CFrame.new(0, cabTop / 2, 0), Vector3.new(6, cabTop, L + 0.6))
	if mesh then
		for _, p in body do
			if p ~= chassis then
				p.Transparency = 1
			end
		end
		Props.weldTo(mesh, chassis)
	end

	model:SetAttribute("Wheels", #wheels)
	model:SetAttribute("Length", L)
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
	local cabFront = -def.length / 2 + HOOD

	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2, 0.5, 1.8)
	-- On top of the bench, driver's side. The chassis center is DECK - 0.4 above the ground.
	seat.CFrame = chassis.CFrame * CFrame.new(-1.2, DECK + 0.95 - (DECK - 0.4), cabFront + CAB_D - 1.1)
	seat.Color = Rustic.Cloth
	seat.Material = Enum.Material.Fabric
	seat.HeadsUpDisplay = false
	seat.MaxSpeed = 0 -- the client controller does the driving
	seat.Torque = 0
	seat:SetAttribute("Truck", true)
	seat.Parent = model

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
	drive.MaxForce = 9000
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
		else
			-- The driver got out: park where it stands.
			steer.CFrame = CFrame.Angles(0, yawOf(chassis.CFrame), 0)
			drive.PlaneVelocity = Vector2.new(0, 0.001)
			drive.PlaneVelocity = Vector2.zero
		end
	end)
	return seat
end

-- Moves an anchored truck (used by the garage drive-out).
function Vehicles.place(model, cframe)
	local chassis = model.PrimaryPart
	chassis.CFrame = cframe * CFrame.new(0, DECK - 0.4, 0)
end

function Vehicles.groundCFrame(model)
	return model.PrimaryPart.CFrame * CFrame.new(0, -(DECK - 0.4), 0)
end

-- Hands the truck to physics and to its owner's client.
function Vehicles.release(model, owner)
	local chassis = model.PrimaryPart
	chassis.Steer.CFrame = CFrame.Angles(0, yawOf(chassis.CFrame), 0)
	chassis.Anchored = false
	pcall(function()
		chassis:SetNetworkOwner(owner)
	end)
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
	for player, model in owned do
		local chassis = model.PrimaryPart
		local offset, size = model:GetAttribute("CargoOffset"), model:GetAttribute("CargoSize")
		if not chassis or not offset or chassis.Anchored then
			continue
		end
		for _, p in workspace:GetPartBoundsInBox(chassis.CFrame * offset, size) do
			local b = Bales.fromPart(p)
			if b and not b.gone and not b.carriedBy and not b.breaking and not now[b] and not b.body.Anchored then
				now[b] = true
				if not riding[b] then
					b.body:SetAttribute("InTruck", true)
				end
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

function Vehicles.init()
	Players.PlayerRemoving:Connect(function(player)
		if owned[player] then
			owned[player]:Destroy()
			owned[player] = nil
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
