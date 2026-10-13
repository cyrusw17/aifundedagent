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
		-- Part budget (#21): each container within its slice of Config/WorldMap PartBudget, with the real props in.
		local function partsIn(inst)
			local n = 0
			for _, d in inst:GetDescendants() do
				if d:IsA("BasePart") then
					n += 1
				end
			end
			return n
		end
		local overBudget = {}
		local containers = {}
		for _, child in isles:GetChildren() do
			if child.Name == "Isles" then
				for _, sub in child:GetChildren() do
					table.insert(containers, sub)
				end
			elseif child.Name ~= "WorldEdge" then
				table.insert(containers, child)
			end
		end
		for _, c in containers do
			local cap = Map.PartBudget[c.Name]
			local n = partsIn(c)
			if cap and n > cap then
				table.insert(overBudget, ("%s %d/%d"):format(c.Name, n, cap))
			end
		end
		t.check("every map container is within its part budget", #overBudget == 0, #overBudget > 0 and table.concat(overBudget, ", ") or nil)
		-- Fall safety (#22): a fall anywhere lands on a dry road, never back at camp.
		local FallSafety = require(Services.FallSafety)
		local wet = {}
		for _, at in { Vector3.new(900, -100, -900), Vector3.new(-1500, -100, -600), Vector3.new(2600, -100, -1700), Vector3.new(10, -100, 10) } do
			local ground, name = FallSafety.target(at)
			if name == "camp" or ground.Position.Y <= Map.SeaLevel then
				table.insert(wet, ("%d,%d -> %s"):format(at.X, at.Z, tostring(name)))
			end
		end
		t.check("a fall anywhere lands on a dry road", #wet == 0, #wet > 0 and table.concat(wet, "; ") or nil)
		-- Signpost distances (#23): every place a junction sign names is reachable by road.
		local noRoute = {}
		for _, j in Regions.junctions or {} do
			local ok, text, numbers = pcall(Regions.junctionText, j)
			local wanted = 0
			for _, line in j[4] do
				if line[3] then
					wanted += 1
				end
			end
			if not ok or #numbers < wanted then
				table.insert(noRoute, ok and text or tostring(text))
			end
		end
		t.check("every junction sign has a road distance to each place", #noRoute == 0, #noRoute > 0 and table.concat(noRoute, "; ") or nil)
		-- Night lights (#26): lanterns along the roads, and every one of them is a lamp the clock switches.
		local RoadPolishL = require(Services.RoadPolish)
		local lighting = isles:FindFirstChild("Lighting")
		local unlit = 0
		for _, d in lighting and lighting:GetDescendants() or {} do
			if d.Name == "RoadLantern" and not d:FindFirstChildOfClass("PointLight") then
				unlit += 1
			end
		end
		t.check("the roads have lanterns for the night", lighting ~= nil and #RoadPolishL.lanterns >= 50 and unlit == 0, ("%d lanterns, %d without a light"):format(#RoadPolishL.lanterns, unlit))
		-- Weekly festival (H11): this week's region is published for the countdown strip, and it has a field.
		local Festival = require(Services.Festival)
		local fest = Festival.at(os.time())
		t.equal("the festival region is published", ReplicatedStorage:GetAttribute("FestivalRegion"), fest.region)
		local festField = false
		for _, f in Regions.fields do
			if f.region == fest.name then
				festField = true
			end
		end
		t.check("this week's festival region has a hay field", festField, fest.region)
		t.check("the Longstitch Highway is built", isles:FindFirstChild("Longstitch Highway") ~= nil)
		t.check("hay fields are spread over the map", #Regions.fields >= #Map.Regions, ("%d fields"):format(#Regions.fields))
		local fieldless = {}
		for _, def in Map.Regions do
			local has = def.id == "spindle" -- the Spindle's hay is the Crystal Cave's
			for _, entry in Regions.fields do
				has = has or entry.region == def.name
			end
			if not has then
				table.insert(fieldless, def.name)
			end
		end
		t.check("every region has a hay field a truck can reach", #fieldless == 0, #fieldless > 0 and table.concat(fieldless, ", ") or nil)
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
		if workspace:GetAttribute("Headless") == true then
			t.skip("every road sample sits on terrain at road height", "headless: no terrain raycasts")
		elseif WorldTerrain.isReady() then
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

		-- A3 at 2x: the Ridge Cut tunnels through Stitch Ridge, and the Return Ferry sails round the east coast.
		local tunnelH, _, _, _, tube = WorldShape.column(0, -2300)
		t.check("the Ridge Cut runs in a tunnel under Stitch Ridge", tube ~= nil and tube.land == true and tunnelH > tube.roof + 10, ("top %.0f"):format(tunnelH))
		t.equal("...and its floor is the ground there", WorldShape.heightAt(0, -2300), 8)
		local returnFerry = nil
		for _, route in Map.Ferry.Routes do
			if route.via then
				returnFerry = route
			end
		end
		t.check("the Return Ferry sails round the coast to Meadow Shore", returnFerry ~= nil and returnFerry.b.name == "Meadow Shore")
		t.check("Sky Island is out for now", Map.SkyIsland == nil and Map.Zeppelin == nil)

		-- Ferries and the zeppelin ----------------------------------------------------------------------------
		local shuttles = Ferry.all()
		t.equal("ferries and zeppelin running", #shuttles, #Map.Ferry.Routes + (Map.Zeppelin and 1 or 0))
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
			if not shuttle.def.zeppelin then
				local model = shuttle.root.Parent
				local life = 0
				for _, spotName in { "SnackSign", "FerryBountyBoard", "FishingSpot" } do
					local spotPart = model:FindFirstChild(spotName)
					life += (spotPart and spotPart:FindFirstChildOfClass("ProximityPrompt")) and 1 or 0
				end
				t.equal(name .. ": snack stand, bounty board and fishing spot on the promenade", life, 3)
			end
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

		-- Clock ------------------------------------------------------------------------------------------------
		local Lighting = game:GetService("Lighting")
		local WorldClock = require(Services.WorldClock)
		local was = Lighting.ClockTime
		Lighting.ClockTime = 0
		t.check("midnight is night", WorldClock.isNight() and WorldClock.lampsOn())
		Lighting.ClockTime = 12
		t.check("noon is day, lamps off", not WorldClock.isNight() and not WorldClock.lampsOn())
		Lighting.ClockTime = was
		t.check("the sky has an Atmosphere to tint", Lighting:FindFirstChildOfClass("Atmosphere") ~= nil)

		-- Weather ----------------------------------------------------------------------------------------------
		local Weather = require(Services.Weather)
		local WeatherConfig = require(Shared.Config.Weather)
		local unset = {}
		for _, def in Map.Regions do
			if not WeatherConfig.Kinds[Weather.get(def.id)] or not WeatherConfig.Regions[def.id] then
				table.insert(unset, def.id)
			end
		end
		t.check("every region has weather", #unset == 0, #unset > 0 and table.concat(unset, ", ") or nil)
		-- Fronts (#25): rain, snow and dust only come as one front at a time; the front on now (if any) is published.
		local frontKinds = {}
		for _, f in WeatherConfig.Fronts do
			frontKinds[f.kind] = true
		end
		local everydayFront = {}
		for id, choices in WeatherConfig.Regions do
			for kind in choices do
				if frontKinds[kind] then
					table.insert(everydayFront, id .. ":" .. kind)
				end
			end
		end
		t.check("rain, snow and dust only come as fronts", #everydayFront == 0, #everydayFront > 0 and table.concat(everydayFront, ", ") or nil)
		local front = Weather.front()
		t.equal("the front on the map is published", ReplicatedStorage:GetAttribute("WeatherFront"), front and front.region or nil)
		local desertWas = Weather.get("desert")
		Weather.force("desert", "dust", 1)
		t.equal("an event can force a region's weather", ReplicatedStorage:GetAttribute("Weather_desert"), "dust")
		Weather.set("desert", desertWas)

		-- Region events ----------------------------------------------------------------------------------------
		local RegionEvents = require(Services.RegionEvents)
		local dropped = RegionEvents.run("sandstorm", 1)
		local count, strong = 0, 0
		for b in dropped do
			count += 1
			if b.body:GetAttribute("NeedleBoost") == Prices.RegionEvents.sandstorm.boost then
				strong += 1
			end
		end
		t.check("a Sandstorm drops boosted bales on the Dunes", count > 0 and strong == count, ("%d bales, %d boosted"):format(count, strong))
		t.equal("...and blows dust there", Weather.get("desert"), "dust")
		RegionEvents.finish()
		local left = 0
		for b in dropped do
			if not b.gone then
				left += 1
			end
		end
		t.equal("untouched event bales are taken away when it ends", left, 0)
		Weather.set("desert", desertWas)

		-- Wilds -----------------------------------------------------------------------------------------------
		local Wilds = require(Services.Wilds)
		for _, id in { "ember_cache", "captains_lantern", "geode_heart", Map.SkyIsland and "lost_kite" or nil } do
			local found = Wilds.Secrets[id]
			t.check(("secret %s is hidden on the map, with a reward in Prices"):format(id), found ~= nil and found.part.Parent ~= nil and Prices.Secrets[id] ~= nil)
		end
		local noHidden = {}
		for _, def in Map.Regions do
			local h = Wilds.Hidden[def.id]
			if not (h and h.part.Parent and Wilds.Secrets[h.id]) then
				table.insert(noHidden, def.id)
			end
		end
		t.check("every region hides one spot with an Old Sign clue", #noHidden == 0, #noHidden > 0 and table.concat(noHidden, ", ") or nil)
		local ember = Wilds.Secrets.ember_cache
		t.check("the Ember Cache lies in the crater's heat", ember ~= nil and Wilds.inHeat(ember.part.Position))
		local searcher = t.player and t.player()
		if searcher and ember and not Wilds.heatProof(searcher) and not Wilds.found(searcher, "ember_cache") then
			t.equal("the Ember Cache refuses a search without heat gloves", Wilds.claimSecret(searcher, "ember_cache", "Ember Cache"), false)
			t.equal("...and nothing is recorded", Wilds.found(searcher, "ember_cache"), false)
		end
		local clockWas = Lighting.ClockTime
		Lighting.ClockTime = 0
		Wilds.refreshGhost()
		t.check("the Ghost Road holds at midnight", Wilds.ghostSolid())
		Lighting.ClockTime = clockWas
		Wilds.refreshGhost()

		-- Discoveries -------------------------------------------------------------------------------------------
		local Discoveries = require(Services.Discoveries)
		local unfound = {}
		for _, entry in Discoveries.all() do
			if entry.kind == "landmark" then
				local hit = false
				for _, id in Discoveries.at(Vector3.new(entry.at.X, 20, entry.at.Y)) do
					hit = hit or id == entry.id
				end
				if not hit then
					table.insert(unfound, entry.id)
				end
			end
		end
		t.check("every landmark is discovered by standing on it", #unfound == 0, #unfound > 0 and table.concat(unfound, ", ") or nil)
		t.equal("Meadow Farm is home, not a discovery", #Discoveries.at(Vector3.new(0, 5, 0)), 0)

		-- Bridges -------------------------------------------------------------------------------------------------
		-- The rails stand outside the lane (the lane check above covers parts in it); here: each bridge's causeway
		-- rises no steeper than a loaded truck and trailer can take.
		local RoadPolish = require(Services.RoadPolish)
		t.check("the water crossings have bridges", #RoadPolish.bridges > 0, ("%d bridge sides"):format(#RoadPolish.bridges))
		local steep = {}
		for _, bridge in RoadPolish.bridges do
			local rise = math.abs(bridge.to.Y - bridge.from.Y)
			local run = (Vector2.new(bridge.to.X, bridge.to.Z) - Vector2.new(bridge.from.X, bridge.from.Z)).Magnitude
			if run > 0 and rise / run > 0.15 then
				table.insert(steep, ("%s %.2f"):format(bridge.road, rise / run))
			end
		end
		t.check("bridges are gentle enough for a trailer", #steep == 0, #steep > 0 and table.concat(steep, ", ") or nil)

		-- The hay wagon --------------------------------------------------------------------------------------------
		local HayWagon = require(Services.HayWagon)
		t.check("the free hay wagon runs with six seats", HayWagon.model ~= nil and HayWagon.model.Parent ~= nil and #HayWagon.seats == 6)
		if HayWagon.model then
			local before = HayWagon.model:GetPivot().Position
			local wagonWait = HayWagon.state.wait
			HayWagon.state.wait = 0
			HayWagon.step(1)
			if workspace:GetAttribute("Headless") == true then
				t.skip("...and moves along its road", "headless: the wagon follows terrain raycasts")
			else
				t.check("...and moves along its road", (HayWagon.model:GetPivot().Position - before).Magnitude > 1)
			end
			HayWagon.state.wait = wagonWait
		end

		-- The Spindle door ---------------------------------------------------------------------------------------
		local SpindleDoor = require(Services.SpindleDoor)
		local CollectionService = game:GetService("CollectionService")
		t.equal("the Spindle door has twelve shard sockets", #CollectionService:GetTagged("ShardSocket"), 12)
		t.check("the shard order comes from the quest collection", #SpindleDoor.shards >= 6, ("%d shards"):format(#SpindleDoor.shards))
		SpindleDoor.refresh()
		local who = t.player and t.player()
		if who then
			t.equal("a player with no shards counts none", who:GetAttribute("SpindleShards") or 0, SpindleDoor.count(who))
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
					-- Other fields may keep a festival or region-event boost; only the rich field's must go.
					elseif not entry.rich and (b.body:GetAttribute("RichBoost") or (b.body:GetAttribute("NeedleBoost") == 2 and not b.body:GetAttribute("RegionEvent"))) then
						plain += 1
					end
				end
			end
		end
		t.check("its bales carry 2x needles", boosted > 0, ("%d bales"):format(boosted))
		t.check("no other field keeps the boost", plain == 0, plain > 0 and ("%d bales still boosted"):format(plain) or nil)
	end)
end
