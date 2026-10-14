--!nonstrict
-- Project health check's suites: every module loads, the world fits the part budget, the canonical bale, and the
-- P0: every truck drives on flat ground and climbs a 20 degree ramp with physics alone (no player needed).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Services = script.Parent.Parent.Services
local Shared = ReplicatedStorage:WaitForChild("Shared")

local PART_BUDGET = 40000
-- tools/headless sets Workspace.Headless: nothing falls or drives there, so the physics checks skip with a reason.
local HEADLESS = workspace:GetAttribute("Headless") == true

return function(SelfTest)
	SelfTest.register("Health", function(t)
		-- Every module loads. They are already required by now, so this re-reports any that errored on load.
		local bad = {}
		local count = 0
		for _, root in { Services, Shared } do
			for _, m in root:GetDescendants() do
				-- Shared.UI is client-only (it reads LocalPlayer), so the server skips it.
				local clientOnly = Shared:FindFirstChild("UI") ~= nil and m:IsDescendantOf(Shared.UI)
				if m:IsA("ModuleScript") and not clientOnly then
					count += 1
					local ok, err = pcall(require, m)
					if not ok then
						table.insert(bad, m:GetFullName() .. ": " .. tostring(err))
					end
				end
			end
		end
		t.check(("all %d modules load"):format(count), #bad == 0, #bad > 0 and table.concat(bad, "; ") or nil)

		local parts = 0
		for _, d in workspace:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
			end
		end
		t.check("Workspace part count is within budget", parts <= PART_BUDGET, ("%d of %d"):format(parts, PART_BUDGET))

		local Prices = require(Shared.Config.Prices)
		local badPrices = {}
		local function walk(tbl, path)
			for k, v in tbl do
				if typeof(v) == "number" and (v ~= v or v < 0 or v == math.huge) then
					table.insert(badPrices, path .. "." .. tostring(k))
				elseif typeof(v) == "table" then
					walk(v, path .. "." .. tostring(k))
				end
			end
		end
		walk(Prices, "Prices")
		t.check("every price is a finite number >= 0", #badPrices == 0, #badPrices > 0 and table.concat(badPrices, ", ") or nil)

		local PropsConfig = require(Shared.Config.Props)
		local folder = ServerStorage:FindFirstChild(PropsConfig.Folder)
		local imported, listed = 0, 0
		for name in PropsConfig.Sizes do
			listed += 1
			if folder and folder:FindFirstChild(name, true) then
				imported += 1
			end
		end
		if imported == 0 then
			t.skip("Rustic props imported", "none in ServerStorage." .. PropsConfig.Folder .. "; the game uses part-built looks")
		else
			t.check("Rustic props imported", true, ("%d of %d listed in Config/Props Sizes"):format(imported, listed))
		end
	end)

	SelfTest.register("Bales", function(t)
		local Bales = require(Services.Bales)
		local spot = t.place()
		local b = Bales.spawn(spot.Position + Vector3.new(0, 3, 0))
		t.cleanup(b.body)
		local size = b.body.Size
		local dims = { size.X, size.Y, size.Z }
		table.sort(dims)
		t.check("bale is 4.6 x 2.6 x 3.2", math.abs(dims[1] - 2.6) < 0.05 and math.abs(dims[2] - 3.2) < 0.05 and math.abs(dims[3] - 4.6) < 0.05, ("%.2f x %.2f x %.2f"):format(size.X, size.Y, size.Z))
		-- A spawned (field) bale rests anchored until someone moves it; set down, it is loose physics.
		t.check("a spawned bale rests anchored", b.body.Anchored)
		Bales.releaseAt(b, CFrame.new(spot.Position + Vector3.new(0, 3, 0)))
		t.check("a set-down bale is free physics (not anchored)", not b.body.Anchored)
		if HEADLESS then
			t.skip("bale settles on the ground", "headless: no physics")
		else
			t.wait(2)
			local restY = b.body.Position.Y - spot.Position.Y
			t.check("bale settles on the ground", restY > 0.5 and restY < 3, ("center %.2f above the pad"):format(restY))
		end
		t.equal("Bales.fromPart finds the bale", Bales.fromPart(b.body), b)
		Bales.consume(b)
		t.wait(0.5)
		t.check("Bales.consume removes it", not b.body.Parent or b.gone, nil)
	end)

	-- Drives like Truck.client.luau does: the steer frame follows the ground under the chassis, and the plane
	-- velocity asks for full speed forward. Returns how far it went forward and the highest point it reached.
	local function driveFor(model, seconds, speed)
		local chassis = model.PrimaryPart
		local drive, steer = chassis:FindFirstChild("Drive"), chassis:FindFirstChild("Steer")
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { model }
		local startPos = chassis.Position
		local topY = startPos.Y
		local connection = RunService.Heartbeat:Connect(function()
			local hit = workspace:Raycast(chassis.Position, Vector3.new(0, -14, 0), params)
			local up = hit and hit.Normal or Vector3.yAxis
			local heading = Vector3.new(0, 0, -1)
			local forward = (heading - up * heading:Dot(up)).Unit
			local right = forward:Cross(up)
			steer.CFrame = CFrame.fromMatrix(Vector3.zero, right, up, -forward)
			drive.PlaneVelocity = Vector2.new(0, -speed)
			-- The same pull Truck.client.luau sets every frame.
			drive.MaxForce = (chassis.AssemblyMass + (model:GetAttribute("PullMass") or 0)) * (workspace.Gravity + 80)
			topY = math.max(topY, chassis.Position.Y)
		end)
		task.wait(seconds)
		connection:Disconnect()
		drive.PlaneVelocity = Vector2.zero
		return startPos.Z - chassis.Position.Z, topY - startPos.Y
	end

	local stubOwner = { Name = "SelfTest", UserId = -1, Parent = nil }

	local function spawnTruck(def, cframe)
		local Vehicles = require(Services.Vehicles)
		local model = Vehicles.build(def, cframe, workspace)
		Vehicles.makeDrivable(model, stubOwner)
		Vehicles.release(model, stubOwner)
		return model
	end

	SelfTest.register("Driving", function(t)
		if HEADLESS then
			t.skip("every truck", "headless: no physics, so nothing drives")
			return
		end
		local Trucks = require(Shared.Config.Trucks)
		local seconds = 2
		for i, def in Trucks do
			local lane = t.center * CFrame.new(-80 + (i - 1) * 35, 0, 80)
			local ok, model = pcall(spawnTruck, def, lane)
			if not t.check(def.id .. " builds and becomes drivable", ok and model and model.PrimaryPart and model.PrimaryPart:FindFirstChild("Drive"), not ok and model or nil) then
				continue
			end
			t.cleanup(model)
			t.wait(0.5)
			local distance = driveFor(model, seconds, def.maxSpeed)
			local want = def.maxSpeed * seconds * 0.4
			t.check(def.id .. " drives forward on flat ground", distance >= want, ("%.1f studs in %d s, want >= %.0f"):format(distance, seconds, want))
		end
	end)

	SelfTest.register("Driving uphill", function(t)
		if HEADLESS then
			t.skip("every truck", "headless: no physics, so nothing drives")
			return
		end
		local Trucks = require(Shared.Config.Trucks)
		local angle, length = 20, 50
		local rise = math.sin(math.rad(angle)) * length
		for i, def in Trucks do
			local laneX = -80 + (i - 1) * 35
			-- The ramp's low edge starts on the pad 6 studs in front of the truck's nose and rises toward -Z.
			local lowEdge = t.center.Position + Vector3.new(laneX, 0, 80 - def.length / 2 - 6)
			local ramp = Instance.new("Part")
			ramp.Name = "SelfTestRamp"
			ramp.Anchored = true
			ramp.Size = Vector3.new(16, 2, length)
			ramp.CFrame = CFrame.new(lowEdge) * CFrame.Angles(math.rad(angle), 0, 0) * CFrame.new(0, -1, -length / 2)
			ramp.Material = Enum.Material.Ground
			ramp.Parent = workspace
			t.cleanup(ramp)
			local ok, model = pcall(spawnTruck, def, t.center * CFrame.new(laneX, 0, 80))
			if not ok then
				t.check(def.id .. " builds", false, model)
				continue
			end
			t.cleanup(model)
			t.wait(0.5)
			local _, climbed = driveFor(model, 4, def.maxSpeed)
			local want = rise * 0.5
			t.check(("%s climbs a %d degree ramp"):format(def.id, angle), climbed >= want, ("rose %.1f studs of %.1f, want >= %.1f"):format(climbed, rise, want))
		end
	end)
end
