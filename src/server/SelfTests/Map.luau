--!nonstrict
-- Full world map's suites: every region built, terrain under every road at the road's height, no solid part in a
-- lane, the ferries and zeppelin running with their fares, a truck that can't pay rolls back to the pier, and the
-- rich field moves on with its 2x needles. Offline twin: tools/mapcheck (no Roblox needed).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Services = script.Parent.Parent.Services
local Shared = ReplicatedStorage:WaitForChild("Shared")

local TERRAIN_WAIT = 90 -- seconds to wait for WorldTerrain to finish before skipping the terrain checks
local ROAD_STEP = 32

return function(SelfTest)
	SelfTest.register("Map", function(t)
		local Map = require(Shared.Config.WorldMap)
		local Prices = require(Shared.Config.Prices)
		local WorldShape = require(Services.WorldShape)
		local WorldTerrain = require(Services.WorldTerrain)
		local WorldMap = require(Services.WorldMap)
		local Regions = require(Services.Regions)
		local Ferry = require(Services.Ferry)

		local root = workspace:FindFirstChild("Needlewood")
		local isles = root and root:FindFirstChild("StitchedIsles")
		t.check("the Stitched Isles folder is built", isles ~= nil)
		if not isles then
			return
		end

		-- Every region -----------------------------------------------------------------------------------------
		local built = isles:FindFirstChild("Isles")
		local missing = {}
		for _, def in Map.Regions do
			local folder = built and built:FindFirstChild(def.name)
			local parts = 0
			for _, d in folder and folder:GetDescendants() or {} do
				if d:IsA("BasePart") then
					parts += 1
				end
			end
			if parts < 20 then
				table.insert(missing, ("%s (%d parts)"):format(def.name, parts))
			end
		end
		t.check(("all %d regions have their trees and landmarks"):format(#Map.Regions), #missing == 0, #missing > 0 and table.concat(missing, ", ") or nil)
		t.check("the Longstitch Highway is built", isles:FindFirstChild("Longstitch Highway") ~= nil)
		t.check("hay fields are spread over the map", #Regions.fields >= #Map.Regions, ("%d fields"):format(#Regions.fields))
		local meadow = root:FindFirstChild("Meadow")
		t.check("Meadow's gates are open", not (meadow and (meadow:FindFirstChild("ClosedGate") or meadow:FindFirstChild("EdgeWall"))))

		-- Roads ------------------------------------------------------------------------------------------------
		local waited = 0
		while not WorldTerrain.isReady() and waited < TERRAIN_WAIT do
			t.wait(2)
			waited += 2
		end
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Include
		rayParams.FilterDescendantsInstances = { workspace.Terrain }
		local overlap = OverlapParams.new()
		overlap.FilterType = Enum.RaycastFilterType.Exclude
		overlap.FilterDescendantsInstances = { workspace.Terrain }

		if not WorldTerrain.isReady() then
			t.skip("roads lie on the terrain", ("terrain still generating after %d s"):format(TERRAIN_WAIT))
		end
		local ferries = isles:FindFirstChild("Ferries") -- piers start on the road ends, level with them
		local holes, blocked, samples = {}, {}, 0
		for _, road in Map.Roads do
			for i = 1, #road.points - 1 do
				local a, b = road.points[i], road.points[i + 1]
				local n = math.max(1, math.floor((b - a).Magnitude / ROAD_STEP))
				for k = 0, n - 1 do
					local p = a:Lerp(b, k / n)
					if WorldShape.inMeadow(p.X, p.Y) then
						continue
					end
					local _, h = WorldShape.nearestRoad(p.X, p.Y)
					if not h then
						continue
					end
					samples += 1
					if WorldTerrain.isReady() then
						local hit = workspace:Raycast(Vector3.new(p.X, h + 60, p.Y), Vector3.new(0, -140, 0), rayParams)
						if not hit or math.abs(hit.Position.Y - h) > 3 then
							table.insert(holes, ("%s at (%d, %d): ground %s, road %.1f"):format(road.name, p.X, p.Y, hit and ("%.1f"):format(hit.Position.Y) or "none", h))
						end
					end
					-- Anything solid and anchored in a 10-stud box above the lane would stop a truck.
					for _, part in workspace:GetPartBoundsInBox(CFrame.new(p.X, h + 4, p.Y), Vector3.new(10, 6, 10), overlap) do
						if part.Anchored and part.CanCollide and part.Transparency < 1 and not (ferries and part:IsDescendantOf(ferries)) then
							table.insert(blocked, ("%s on the %s at (%d, %d)"):format(part:GetFullName(), road.name, p.X, p.Y))
							break
						end
					end
				end
			end
		end
		if WorldTerrain.isReady() then
			t.check(("every road sample sits on terrain at road height (%d samples)"):format(samples), #holes == 0, #holes > 0 and table.concat(holes, "; ", 1, math.min(#holes, 8)) or nil)
		end
		t.check("no solid part stands in a road lane", #blocked == 0, #blocked > 0 and table.concat(blocked, "; ", 1, math.min(#blocked, 8)) or nil)

		-- Every road starts at Meadow's edge, on another road, on a plaza or port (a flat zone), or at the highway.
		local loose = {}
		for r, road in Map.Roads do
			local start = road.points[1]
			local joined = WorldShape.meadowDistance(start.X, start.Y) < 4 or WorldShape.highwayDistance(start.X, start.Y) < Map.Highway.width
			for _, zone in Map.Flat do
				if WorldShape.rectDistance(start.X, start.Y, zone.min, zone.max) <= 0 then
					joined = true
				end
			end
			for other = 1, #Map.Roads do
				local pts = Map.Roads[other].points
				for i = 1, #pts - 1 do
					if other ~= r and WorldShape.segment(start.X, start.Y, pts[i].X, pts[i].Y, pts[i + 1].X, pts[i + 1].Y) < 4 then
						joined = true
					end
				end
			end
			if not joined then
				table.insert(loose, road.name)
			end
		end
		t.check("every road starts at Meadow, a road, a plaza or the highway", #loose == 0, #loose > 0 and table.concat(loose, ", ") or nil)

		-- Ferries and the zeppelin ----------------------------------------------------------------------------
		local shuttles = Ferry.all()
		t.equal("ferries and zeppelin running", #shuttles, #Map.Ferry.Routes + 1)
		for _, shuttle in shuttles do
			local name = shuttle.def.name
			t.check(name .. ": deck is a free physics body held by its course", not shuttle.root.Anchored and shuttle.align.Parent ~= nil)
			local want = shuttle.def.zeppelin and Prices.Travel.zeppelin or Prices.Travel.ferry
			t.equal(name .. ": fare matches Prices.Travel", shuttle.def.fare, want)

			-- A truck that can't pay is rolled back onto the pier. A stand-in "truck": one free part on the deck.
			local deckTop = shuttle.root.CFrame * CFrame.new(0, shuttle.root.Size.Y / 2 + 2, 0)
			local truck = Instance.new("Model")
			truck.Name = "SelfTestTruck"
			local chassis = Instance.new("Part")
			chassis.Size = Vector3.new(8, 2, 14)
			chassis.CFrame = deckTop
			chassis.Parent = truck
			truck.PrimaryPart = chassis
			truck.Parent = workspace
			t.cleanup(truck)
			t.check(name .. ": a truck on the deck counts as on board", Ferry.onDeck(shuttle, truck))
			local stop = shuttle.stops[1]
			for _, s in shuttle.stops do
				if (s.cframe.Position - shuttle.root.Position).Magnitude < (stop.cframe.Position - shuttle.root.Position).Magnitude then
					stop = s
				end
			end
			Ferry.sendBack(truck, stop)
			local landed = chassis.Position
			local target = stop.edge + stop.inland * 20
			t.check(name .. ": an unpaid truck is rolled off the deck", not Ferry.onDeck(shuttle, truck))
			t.near(name .. ": ...onto the pier at " .. stop.name, (Vector3.new(landed.X, 0, landed.Z) - Vector3.new(target.X, 0, target.Z)).Magnitude, 0, 1)
			truck:Destroy()
		end

		-- Rich field -------------------------------------------------------------------------------------------
		if #Regions.fields < 2 then
			t.skip("the rich field moves on", "fewer than two hay fields")
			return
		end
		local before = ReplicatedStorage:GetAttribute("RichField")
		WorldMap.rotateRich()
		local after = ReplicatedStorage:GetAttribute("RichField")
		t.check("the rich field moves to another field", after ~= nil and after ~= before, tostring(after))
		t.check("the gold beacon stands over it", isles:FindFirstChild("RichFieldBeacon") ~= nil)
		local boosted, plain = 0, 0
		for _, entry in Regions.fields do
			for b in entry.bales do
				if b.body and b.body.Parent then
					if entry.rich and b.body:GetAttribute("NeedleBoost") == 2 then
						boosted += 1
					elseif not entry.rich and b.body:GetAttribute("NeedleBoost") then
						plain += 1
					end
				end
			end
		end
		t.check("its bales carry 2x needles", boosted > 0, ("%d bales"):format(boosted))
		t.check("no other field keeps the boost", plain == 0, plain > 0 and ("%d bales still boosted"):format(plain) or nil)
	end)
end
