--!nonstrict
-- Self-tests for the starting biome's trucks (Starting biome thread): build and settle, drive force, hitching, the
-- bale chute, the 9-bale haul from the chute to the dock and the HAY SELL SHOP payout, entering and leaving the
-- seat, and the dealer purchase. Run by SelfTest.luau (set the Workspace attribute RunSelfTests in Studio).
-- Tests that need a player skip when nobody has joined.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Services = script.Parent.Parent.Services
-- tools/headless sets Workspace.Headless: nothing falls or drives there, so the checks that need bales to settle or
-- trucks to roll skip with a reason (as Conveyor and Health do).
local HEADLESS = workspace:GetAttribute("Headless") == true
local NO_PHYSICS = "headless run: no physics, so bales do not fall and trucks do not roll"

return function(SelfTest)
	local Vehicles = require(Services.Vehicles)
	local Bales = require(Services.Bales)
	local Chutes = require(Services.Chutes)
	local Dock = require(Services.Dock)
	local Data = require(Services.Data)

	local function spawnPickupLike(t, id, cframe, owner)
		local model = Vehicles.build(Vehicles.get(id), cframe, workspace)
		t.cleanup(model)
		Vehicles.makeDrivable(model, owner or { Name = "SelfTest", UserId = -1 })
		Vehicles.release(model, owner)
		return model
	end
	local function spawnPickup(t, cframe, owner)
		return spawnPickupLike(t, "rusty_pickup", cframe, owner)
	end

	-- The loose bales inside a truck's cargo box.
	local function balesIn(model)
		local chassis = model.PrimaryPart
		local offset, size = model:GetAttribute("CargoOffset"), model:GetAttribute("CargoSize")
		local found = {}
		for _, p in workspace:GetPartBoundsInBox(chassis.CFrame * offset, size) do
			local b = Bales.fromPart(p)
			if b and p == b.body and not b.gone then
				found[b] = true
			end
		end
		local n = 0
		for _ in found do
			n += 1
		end
		return n, found
	end

	-- Drives straight ahead like Truck.client.luau (steer frame on the ground normal, full plane velocity).
	local function driveFor(model, seconds, speed)
		local chassis = model.PrimaryPart
		local drive, steer = chassis:FindFirstChild("Drive"), chassis:FindFirstChild("Steer")
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { model }
		local heading = chassis.CFrame.LookVector * Vector3.new(1, 0, 1)
		heading = heading.Unit
		local start = chassis.Position
		local connection = RunService.Heartbeat:Connect(function()
			local hit = workspace:Raycast(chassis.Position, Vector3.new(0, -14, 0), params)
			local up = hit and hit.Normal or Vector3.yAxis
			local forward = (heading - up * heading:Dot(up)).Unit
			steer.CFrame = CFrame.fromMatrix(Vector3.zero, forward:Cross(up), up, -forward)
			drive.PlaneVelocity = Vector2.new(0, -speed)
		end)
		task.wait(seconds)
		connection:Disconnect()
		drive.PlaneVelocity = Vector2.zero
		return (chassis.Position - start):Dot(heading)
	end

	SelfTest.register("Biome", function(t)
		-- Build, settle and drive force -------------------------------------------------------------------------
		local truck = spawnPickup(t, t.place())
		local chassis = truck.PrimaryPart
		t.near("pickup track matches the Blender rig", truck:GetAttribute("Track"), 3.9, 0.01)
		t.wait(1.5)
		t.check("pickup settles upright on its wheels", chassis.CFrame.UpVector.Y > 0.97, ("up.Y %.3f"):format(chassis.CFrame.UpVector.Y))
		local rest = chassis.Position.Y - t.center.Position.Y
		t.check("pickup rests on the ground, not in it", rest > 1 and rest < 4, ("chassis %.2f above the pad"):format(rest))
		local need = chassis.AssemblyMass * workspace.Gravity * 1.2
		t.check("drive force lifts the truck's own weight with room to spare", chassis.Drive.MaxForce >= need, ("%.0f, want >= %.0f"):format(chassis.Drive.MaxForce, need))

		-- Every truck with a bale bed holds its Blender bed's bales a layer (along x across).
		for id, want in { rusty_pickup = 9, farm_flatbed = 9, box_truck = 12, heavy_hauler = 15 } do
			local m = Vehicles.build(Vehicles.get(id), t.place(), workspace)
			t.cleanup(m)
			local size = m:GetAttribute("CargoSize")
			local slots = size and math.floor((size.X + 0.3) / 3.2) * math.floor((size.Z + 0.3) / 4.6) or 0
			t.equal(("%s bed holds %d bales a layer"):format(id, want), slots, want)
			m:Destroy()
		end

		-- Hitch and unhitch ------------------------------------------------------------------------------------
		local trailerDef = Vehicles.getTrailer("small_trailer")
		local trailer = Vehicles.buildTrailer(trailerDef, chassis.CFrame * CFrame.new(0, -chassis.Position.Y + t.center.Position.Y, 30), workspace)
		t.cleanup(trailer)
		-- A built trailer gets its coupler and hitch joint when it goes live (bought at the dealer or spawned owned).
		Vehicles.makeTrailerLive(trailer, { Name = "SelfTest", UserId = -1 })
		t.check("hitch returns true", Vehicles.hitch(truck, trailer))
		local ball = chassis:FindFirstChild("HitchAttachment")
		local coupler = trailer.PrimaryPart:FindFirstChild("CouplerAttachment")
		local joint = trailer.PrimaryPart:FindFirstChild("Hitch")
		if t.check("truck has a hitch ball and the trailer a coupler and joint", ball ~= nil and coupler ~= nil and joint ~= nil) then
			t.near("coupler sits on the hitch ball", (ball.WorldPosition - coupler.WorldPosition).Magnitude, 0, 0.3)
			t.check("hitch joint is on", joint.Enabled)
			Vehicles.unhitch(trailer)
			t.check("unhitch turns the joint off and clears HitchedTo", not joint.Enabled and trailer:GetAttribute("HitchedTo") == nil)
		end
		trailer:Destroy()

		-- Bale chute: one pull fills the bottom layer --------------------------------------------------------
		local lane = t.place()
		local truck2 = spawnPickup(t, lane)
		t.wait(1)
		local cargoAt = truck2.PrimaryPart.CFrame * truck2:GetAttribute("CargoOffset")
		-- Stand the chute 4 studs under the bed's middle, wherever the truck is: a headless run has no physics, so the
		-- truck may still hang where it was built instead of on the pad.
		local under = Vector3.new(cargoAt.X, cargoAt.Y - 4, cargoAt.Z)
		local chute = Chutes.make(workspace, CFrame.lookAt(under, under + lane.LookVector))
		t.cleanup(chute.model)
		local dropping = Chutes.pull(chute, nil)
		t.equal("chute drops a full layer into the pickup bed", dropping, 9)
		if HEADLESS then
			t.skip("chute bales land in the bed and stay through a drive", NO_PHYSICS)
			t.wait(9 * 0.35 + 0.5)
			for b in select(2, balesIn(truck2)) do
				t.cleanup(b.body) -- the dropped bales still go when the suite ends
			end
		else
			t.wait(9 * 0.35 + 2.5)
			local n, loaded = balesIn(truck2)
			t.equal("9 bales lie in the bed", n, 9)
			for b in loaded do
				t.cleanup(b.body)
			end
			t.check("chute bales are loose physics, never welded", (function()
				for b in loaded do
					if b.body.Anchored or b.body:FindFirstChildWhichIsA("WeldConstraint") then
						return false
					end
				end
				return true
			end)())
			local moved = driveFor(truck2, 3, 24)
			t.wait(1)
			t.check("loaded pickup drives forward", moved > 20, ("%.1f studs in 3 s"):format(moved))
			local kept = balesIn(truck2)
			t.equal("all 9 bales are still in the bed after the drive", kept, 9)
		end

		-- The haul: 9 bales backed up to the dock, unloaded, paid --------------------------------------------
		local player = t.player(5)
		local park = Dock.parkFrame(Vehicles.get("rusty_pickup").length)
		if not park then
			t.skip("dock haul", "no dock in this place")
		elseif HEADLESS then
			t.skip("dock haul: unload and payout", NO_PHYSICS)
		else
			local truck3 = spawnPickup(t, park)
			t.wait(1)
			local cargo = truck3.PrimaryPart.CFrame * truck3:GetAttribute("CargoOffset")
			local size = truck3:GetAttribute("CargoSize")
			local count = 0
			for k = 1, 3 do
				for i = 1, 3 do
					local slot = cargo * CFrame.new((i - 2) * 3.25, -size.Y / 2 + 1.3, (k - 2) * 4.7) * CFrame.Angles(0, math.pi / 2, 0)
					local b = Bales.spawn(Vector3.zero, false, false)
					b.ownerId = player and player.UserId
					b.body.CFrame = slot + Vector3.new(0, 0.3, 0)
					b.body.Anchored = false
					t.cleanup(b.body)
					count += 1
				end
			end
			t.wait(2)
			t.equal("9 bales loaded at the dock", (balesIn(truck3)), count)
			t.check("dock sees the cargo", Dock.hasCargo())
			local state = player and Data.get(player)
			local earned = state and state.bank and state.bank.earned or 0
			local done = false
			t.check("dock starts unloading", Dock.unload(function()
				done = true
			end))
			t.wait(1)
			t.check("tailgate opens at the dock", truck3:GetAttribute("TailgateIsOpen") == true)
			local deadline = os.clock() + 35
			while not done and os.clock() < deadline do
				t.wait(0.5)
			end
			t.equal("bed is empty after unloading", (balesIn(truck3)), 0)
			if state then
				local paidBy = os.clock() + 30
				while (state.bank and state.bank.earned or 0) <= earned and os.clock() < paidBy do
					t.wait(0.5)
				end
				local got = (state.bank and state.bank.earned or 0) - earned
				t.check("HAY SELL SHOP pays for the hauled hay", got > 0, ("earned $%d"):format(got))
			else
				t.skip("haul payout", "no player joined, so nobody to pay")
			end
		end

		-- Seat and dealer: need a player with a character -------------------------------------------------------
		local character = player and player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not humanoid or not root then
			t.skip("enter and leave the seat", "no player character")
			t.skip("dealer purchase", "no player character")
			return
		end
		local home = root.CFrame
		local truck4 = spawnPickup(t, t.place(), player)
		t.wait(1)
		local seat = truck4:FindFirstChild("DriverSeat", true)
		root.CFrame = seat.CFrame * CFrame.new(-4, 1, 0)
		t.wait(0.3)
		seat:Sit(humanoid)
		t.wait(0.6)
		t.check("player sits in the driver seat", seat.Occupant == humanoid)
		local weld = seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
		humanoid.Sit = false
		t.wait(0.6)
		t.check("player leaves the seat", seat.Occupant == nil)
		-- The seat rests 1.5 s after the driver gets out (Vehicles makeDrivable) before the prompt comes back.
		t.wait(1.5)
		local prompt = seat:FindFirstChild("DrivePrompt")
		t.check("Drive prompt is back after leaving", not prompt or prompt.Enabled)

		local Dealer = require(Services.Dealer)
		local spot = Dealer.counterPosition and Dealer.counterPosition()
		local state = Data.get(player)
		if not spot or not Dealer.buy or not state then
			t.skip("dealer purchase", "no dealer counter or save loaded")
		else
			local had = table.find(state.trucks, "rusty_pickup") ~= nil
			root.CFrame = CFrame.new(spot + Vector3.new(0, 3, 0))
			t.wait(0.3)
			local ok, message = Dealer.buy(player, "rusty_pickup")
			t.check("dealer sells the Rusty Pickup", ok, message)
			local deadline = os.clock() + 15
			local bought = Vehicles.ownedBy(player)
			while os.clock() < deadline and (not bought or not bought.PrimaryPart or bought.PrimaryPart.Anchored) do
				t.wait(0.5)
				bought = Vehicles.ownedBy(player)
			end
			t.check("the bought truck rolls out of the garage as free physics", bought and bought.PrimaryPart and not bought.PrimaryPart.Anchored)
			local bseat = bought and bought:FindFirstChild("DriverSeat", true)
			local bprompt = bseat and bseat:FindFirstChild("DrivePrompt")
			t.check("buyer is seated, or can get in", bseat and (bseat.Occupant == humanoid or (bprompt and bprompt.Enabled)))
			t.check("the truck is in the save", table.find(state.trucks, "rusty_pickup") ~= nil)
			if not had then
				-- Leave the save as it was: the test truck and its price go back.
				table.remove(state.trucks, table.find(state.trucks, "rusty_pickup"))
				local Bank = require(Services.Bank)
				local price = Vehicles.get("rusty_pickup").price
				if not require(ReplicatedStorage.Shared.Config.Game).InfiniteMoney then
					Bank.give(player, price, "Self-test refund")
				end
				if bought then
					bought:Destroy()
				end
			end
		end
		if humanoid.SeatPart then
			humanoid.Sit = false
		end
		t.wait(0.5)
		root.CFrame = home
	end)

	-- Drops a full bottom layer of loose bales into a bed. Returns the bales and their total mass.
	local function fillLayer(t, model)
		local chassis = model.PrimaryPart
		local cargo = chassis.CFrame * model:GetAttribute("CargoOffset")
		local size = model:GetAttribute("CargoSize")
		local across = math.floor((size.X + 0.3) / 3.2)
		local along = math.floor((size.Z + 0.3) / 4.6)
		local mass = 0
		for k = 1, along do
			for i = 1, across do
				local x = (i - (across + 1) / 2) * math.min(3.25, size.X / across)
				local z = (k - (along + 1) / 2) * math.min(4.7, size.Z / along)
				local b = Bales.spawn(Vector3.zero, false, false)
				b.body.CFrame = cargo * CFrame.new(x, -size.Y / 2 + 1.5, z) * CFrame.Angles(0, math.pi / 2, 0)
				b.body.Anchored = false
				t.cleanup(b.body)
				mass += b.body.AssemblyMass
			end
		end
		return across * along, mass
	end

	local function ramp(t, lowEdge, angle, length)
		local r = Instance.new("Part")
		r.Name = "SelfTestRamp"
		r.Anchored = true
		r.Size = Vector3.new(18, 2, length)
		r.CFrame = CFrame.new(lowEdge) * CFrame.Angles(math.rad(angle), 0, 0) * CFrame.new(0, -1, -length / 2)
		r.Material = Enum.Material.Ground
		r.Parent = workspace
		t.cleanup(r)
		return r
	end

	-- Loaded climbs: every buyable bale truck with a full bottom layer, and the pickup pulling a loaded Small Trailer,
	-- up a 20 degree ramp with physics alone. The bales must stay in and the truck must rise half the ramp.
	SelfTest.register("Biome loaded climb", function(t)
		if HEADLESS then
			t.skip("loaded trucks climb a 20 degree ramp", NO_PHYSICS)
			return
		end
		local angle, length = 20, 50
		local rise = math.sin(math.rad(angle)) * length
		local runs = {}
		local lane = 0
		for _, def in require(ReplicatedStorage.Shared.Config.Trucks) do
			if not def.available then
				continue
			end
			lane += 1
			local laneX = -80 + (lane - 1) * 32
			local stand = t.center * CFrame.new(laneX, 0, 80)
			ramp(t, (stand * CFrame.new(0, 0, -def.length / 2 - 6)).Position, angle, length)
			local truck = spawnPickupLike(t, def.id, stand)
			table.insert(runs, { def = def, truck = truck })
			if def.id == "rusty_pickup" then
				-- A second pickup in its own lane with a hitched, loaded Small Trailer.
				lane += 1
				local laneX2 = -80 + (lane - 1) * 32
				local stand2 = t.center * CFrame.new(laneX2, 0, 60)
				ramp(t, (stand2 * CFrame.new(0, 0, -def.length / 2 - 6)).Position, angle, length)
				local truck2 = spawnPickupLike(t, def.id, stand2)
				local tdef = Vehicles.getTrailer("small_trailer")
				local trailer = Vehicles.buildTrailer(tdef, stand2 * CFrame.new(0, 0, 25), workspace)
				t.cleanup(trailer)
				Vehicles.makeTrailerLive(trailer, { Name = "SelfTest", UserId = -1 })
				Vehicles.hitch(truck2, trailer)
				table.insert(runs, { def = def, truck = truck2, trailer = trailer, label = "rusty_pickup + loaded small_trailer" })
			end
		end
		t.wait(1)
		for _, run in runs do
			local n, mass = fillLayer(t, run.truck)
			run.count = n
			if run.trailer then
				local tn, tmass = fillLayer(t, run.trailer)
				run.trailerCount = tn
				mass += tmass + run.trailer.PrimaryPart.AssemblyMass
				for _, p in run.trailer:GetChildren() do
					if p.Name == "Wheel" and p:IsA("BasePart") then
						mass += p.AssemblyMass
					end
				end
			end
			Vehicles.setDriveForce(run.truck, mass)
		end
		t.wait(2)
		for _, run in runs do
			local chassis = run.truck.PrimaryPart
			run.startY = chassis.Position.Y
			run.top = run.startY
			task.spawn(function()
				local c = RunService.Heartbeat:Connect(function()
					run.top = math.max(run.top, chassis.Position.Y)
				end)
				driveFor(run.truck, 4, run.def.maxSpeed)
				c:Disconnect()
				run.done = true
			end)
		end
		local deadline = os.clock() + 8
		repeat
			t.wait(0.25)
			local all = true
			for _, run in runs do
				all = all and run.done
			end
		until all or os.clock() > deadline
		t.wait(1)
		for _, run in runs do
			local name = run.label or run.def.id .. " loaded"
			local climbed = run.top - run.startY
			t.check(("%s climbs a %d degree ramp"):format(name, angle), climbed >= rise * 0.5, ("rose %.1f of %.1f"):format(climbed, rise))
			t.equal(name .. ": bales stay in the bed", (balesIn(run.truck)), run.count)
			if run.trailer then
				t.equal(name .. ": bales stay in the trailer", (balesIn(run.trailer)), run.trailerCount)
			end
		end
	end)

	-- Side-slope hold: parked across a 15 degree slope with no throttle, the truck must not creep sideways.
	SelfTest.register("Biome side slope", function(t)
		if HEADLESS then
			t.skip("truck holds a 15 degree side slope", NO_PHYSICS)
			return
		end
		local angle = 15
		local slope = Instance.new("Part")
		slope.Name = "SelfTestSlope"
		slope.Anchored = true
		slope.Size = Vector3.new(40, 2, 50)
		slope.CFrame = t.center * CFrame.new(0, 6, 0) * CFrame.Angles(0, 0, math.rad(angle))
		slope.Material = Enum.Material.Ground
		slope.Parent = workspace
		t.cleanup(slope)
		local ground = slope.CFrame * CFrame.new(0, 1, 0)
		local truck = spawnPickupLike(t, "rusty_pickup", ground)
		local chassis = truck.PrimaryPart
		t.wait(1)
		local start = chassis.Position
		driveFor(truck, 5, 0)
		local drift = (chassis.Position - start) * Vector3.new(1, 0, 1)
		t.check(("pickup holds on a %d degree side slope for 5 s"):format(angle), drift.Magnitude < 1, ("drifted %.2f studs"):format(drift.Magnitude))
		t.check("pickup stays on its wheels on the side slope", chassis.CFrame.UpVector.Y > 0.9, ("up.Y %.2f"):format(chassis.CFrame.UpVector.Y))
	end)

	-- Every buyable truck tier: spawns as a saved rig would, flips back onto its wheels from its side, and tows to
	-- the dealer lot; a second tow inside the cooldown is refused.
	SelfTest.register("Biome recovery", function(t)
		local Meadow = require(ReplicatedStorage.Shared.Config.Meadow)
		local ChuteCfg = require(ReplicatedStorage.Shared.Config.Chutes)
		local lane = 0
		for _, def in require(ReplicatedStorage.Shared.Config.Trucks) do
			if not def.available then
				continue
			end
			lane += 1
			-- A stand-in owner per truck, so each has its own cooldowns and its own slot in Vehicles.
			local owner = { Name = "SelfTest" .. lane, UserId = -100 - lane }
			local stand = t.center * CFrame.new(-80 + (lane - 1) * 35, 0, -40)
			local ok, truck = pcall(Vehicles.spawnOwned, owner, def.id, stand)
			if not t.check(def.id .. " spawns as an owned rig", ok and truck ~= nil, not ok and truck or nil) then
				continue
			end
			t.cleanup(truck)
			local chassis = truck.PrimaryPart
			t.wait(1)
			truck:PivotTo(chassis.CFrame * CFrame.new(0, 3, 0) * CFrame.Angles(0, 0, math.rad(95)))
			t.wait(2)
			t.check(def.id .. " lies on its side for the flip test", chassis.CFrame.UpVector.Y < 0.5, ("up.Y %.2f"):format(chassis.CFrame.UpVector.Y))
			local flipped, why = Vehicles.recover(owner, "flip")
			t.check(def.id .. " flip is accepted", flipped, why)
			t.wait(1.5)
			t.check(def.id .. " is upright after the flip", chassis.CFrame.UpVector.Y > 0.95, ("up.Y %.2f"):format(chassis.CFrame.UpVector.Y))
			-- Upright on flat ground: it must fit through a bale chute's lane (Config/Chutes, the mesh's legs and beams).
			local _, box = truck:GetBoundingBox()
			t.check(def.id .. " fits under a bale chute", box.Y < ChuteCfg.Clearance and box.X < ChuteCfg.LaneWidth, ("%.1f wide x %.1f tall, lane %.2f x %.2f"):format(box.X, box.Y, ChuteCfg.LaneWidth, ChuteCfg.Clearance))
			local towed, msg = Vehicles.recover(owner, "tow")
			t.check(def.id .. " tow is accepted", towed, msg)
			t.wait(1)
			local off = (chassis.Position - Meadow.TowSpot) * Vector3.new(1, 0, 1)
			t.check(def.id .. " lands on the dealer lot", off.Magnitude < 4, ("%.1f studs from the tow spot"):format(off.Magnitude))
			t.check(def.id .. " a second tow waits for the cooldown", not (Vehicles.recover(owner, "tow")))
			truck:Destroy()
			t.wait(0.5)
		end
	end)
end
