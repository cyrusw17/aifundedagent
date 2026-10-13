--!nonstrict
-- Self-tests for the starting biome's trucks (Starting biome thread): build and settle, drive force, hitching, the
-- bale chute, the 9-bale haul from the chute to the dock and the HAY SELL SHOP payout, entering and leaving the
-- seat, and the dealer purchase. Run by SelfTest.luau (set the Workspace attribute RunSelfTests in Studio).
-- Tests that need a player skip when nobody has joined.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Services = script.Parent.Parent.Services

return function(SelfTest)
	local Vehicles = require(Services.Vehicles)
	local Bales = require(Services.Bales)
	local Chutes = require(Services.Chutes)
	local Dock = require(Services.Dock)
	local Data = require(Services.Data)

	local function spawnPickup(t, cframe, owner)
		local model = Vehicles.build(Vehicles.get("rusty_pickup"), cframe, workspace)
		t.cleanup(model)
		Vehicles.makeDrivable(model, owner or { Name = "SelfTest", UserId = -1 })
		Vehicles.release(model, owner)
		return model
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

		-- Every truck with a bale bed holds 9 bales a layer (3 along x 3 across).
		for _, id in { "rusty_pickup", "farm_flatbed" } do
			local m = Vehicles.build(Vehicles.get(id), t.place(), workspace)
			t.cleanup(m)
			local size = m:GetAttribute("CargoSize")
			local slots = size and math.floor((size.X + 0.3) / 3.2) * math.floor((size.Z + 0.3) / 4.6) or 0
			t.equal(id .. " bed holds 9 bales a layer", slots, 9)
			m:Destroy()
		end

		-- Hitch and unhitch ------------------------------------------------------------------------------------
		local trailerDef = Vehicles.getTrailer("small_trailer")
		local trailer = Vehicles.buildTrailer(trailerDef, chassis.CFrame * CFrame.new(0, -chassis.Position.Y + t.center.Position.Y, 30), workspace)
		t.cleanup(trailer)
		t.check("hitch returns true", Vehicles.hitch(truck, trailer))
		local ball = chassis:FindFirstChild("HitchAttachment")
		local coupler = trailer.PrimaryPart:FindFirstChild("CouplerAttachment")
		t.near("coupler sits on the hitch ball", (ball.WorldPosition - coupler.WorldPosition).Magnitude, 0, 0.3)
		t.check("hitch joint is on", trailer.PrimaryPart.Hitch.Enabled)
		Vehicles.unhitch(trailer)
		t.check("unhitch turns the joint off and clears HitchedTo", not trailer.PrimaryPart.Hitch.Enabled and trailer:GetAttribute("HitchedTo") == nil)
		trailer:Destroy()

		-- Bale chute: one pull fills the bottom layer --------------------------------------------------------
		local lane = t.place()
		local truck2 = spawnPickup(t, lane)
		t.wait(1)
		local cargoAt = truck2.PrimaryPart.CFrame * truck2:GetAttribute("CargoOffset")
		local chute = Chutes.make(workspace, CFrame.lookAt(Vector3.new(cargoAt.X, lane.Y, cargoAt.Z), Vector3.new(cargoAt.X, lane.Y, cargoAt.Z) + lane.LookVector))
		t.cleanup(chute.model)
		local dropping = Chutes.pull(chute, nil)
		t.equal("chute drops a full layer into the pickup bed", dropping, 9)
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

		-- The haul: 9 bales backed up to the dock, unloaded, paid --------------------------------------------
		local player = t.player(5)
		local park = Dock.parkFrame(Vehicles.get("rusty_pickup").length)
		if not park then
			t.skip("dock haul", "no dock in this place")
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
end
