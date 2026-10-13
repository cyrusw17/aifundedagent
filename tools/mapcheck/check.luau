local t0 = os.clock()
local world = Instance.new("Folder")
world.Name = "Needlewood"
world.Parent = workspace
local meadow = Instance.new("Folder")
meadow.Name = "Meadow"
meadow.Parent = world
local WorldMap = require({ __path = "Services.WorldMap" })
WorldMap.build(world)
local isles = world:FindFirstChild("StitchedIsles")
local function count(folder)
	local parts, models, guis, lights = 0, 0, 0, 0
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then parts += 1 elseif d.ClassName == "Model" then models += 1 elseif d:IsA("LayerCollector") then guis += 1 elseif d:IsA("Light") then lights += 1 end
	end
	return parts, models, guis, lights
end
for _, child in isles:GetChildren() do
	local p, m, g, l = count(child)
	print(("%-22s parts %6d  models %5d  guis %4d  lights %3d"):format(child.Name, p, m, g, l))
	if child.Name == "Isles" then
		for _, sub in child:GetChildren() do
			local p2 = count(sub)
			print(("    %-26s parts %6d"):format(sub.Name, p2))
		end
	end
end
local p, m, g, l = count(isles)
print(("TOTAL parts %d models %d guis %d lights %d; field bales %d; time %.2fs; warnings %d"):format(p, m, g, l, BALES, os.clock() - t0, #warnings))
for tag, n in TAGS do print("tag", tag, n) end
local Shape = require({ __path = "Services.WorldShape" })
local Map = require({ __path = "Shared.Config.WorldMap" })
local half = Map.RoadWidth / 2 - 1
local n = 0
for _, p in isles:FindFirstChild("Isles"):GetDescendants() do
	if p:IsA("BasePart") and p.Anchored and p.CanCollide and p.Transparency < 1 then
		local c, size = p.CFrame, p.Size
		local s = Vector3.new(math.abs(size.X), math.abs(size.Y), math.abs(size.Z))
		for _, o in { Vector3.zero, Vector3.new(s.X/2,0,s.Z/2), Vector3.new(-s.X/2,0,s.Z/2), Vector3.new(s.X/2,0,-s.Z/2), Vector3.new(-s.X/2,0,-s.Z/2) } do
			local at = c * (o * 0.9)
			local d, h, name = Shape.nearestRoad(at.X, at.Z)
			if d and d < half and c.Y + 4 > h + 0.6 and c.Y - 4 < h + 9 then
				n += 1
				print("BLOCK", p:GetFullName(), math.floor(at.X), math.floor(at.Z), name, math.floor(d), math.floor(c.Y - h))
				break
			end
		end
	end
end
print("blocking", n)

-- Every road starts at Meadow's edge, on another road, on a flat zone (plaza, port) or at the highway.
local loose = 0
for r, road in Map.Roads do
	local start = road.points[1]
	local joined = Shape.meadowDistance(start.X, start.Y) < 4 or Shape.highwayDistance(start.X, start.Y) < Map.Highway.width
	for _, zone in Map.Flat do
		if Shape.rectDistance(start.X, start.Y, zone.min, zone.max) <= 0 then
			joined = true
		end
	end
	for other = 1, #Map.Roads do
		local pts = Map.Roads[other].points
		for i = 1, #pts - 1 do
			if other ~= r and Shape.segment(start.X, start.Y, pts[i].X, pts[i].Y, pts[i + 1].X, pts[i + 1].Y) < 4 then
				joined = true
			end
		end
	end
	if not joined then
		loose += 1
		print("WARN loose road start", road.name, start.X, start.Y)
	end
end
print("loose road starts", loose)

-- The clock: night is night, noon is not, lamps follow.
local WorldClock = require({ __path = "Services.WorldClock" })
local Lighting = game:GetService("Lighting")
local clockOk = true
for _, case in { { 0, true, true }, { 12, false, false }, { 18.5, false, true }, { 21, true, true }, { 6.5, false, false } } do
	Lighting.ClockTime = case[1]
	if WorldClock.isNight() ~= case[2] or WorldClock.lampsOn() ~= case[3] then
		clockOk = false
		print("WARN clock wrong at hour", case[1], WorldClock.isNight(), WorldClock.lampsOn())
	end
end
Lighting.ClockTime = 23.5
if WorldClock.phase() ~= "midnight" then clockOk = false end
Lighting.ClockTime = 18
if WorldClock.phase() ~= "dusk" then clockOk = false end
print("clock", clockOk and "ok" or "WRONG", "atmosphere", Lighting:FindFirstChildOfClass("Atmosphere") and "made" or "missing")

-- Weather: every region has a known kind on the board, and an event can force one.
local Weather = require({ __path = "Services.Weather" })
local WeatherConfig = require({ __path = "Shared.Config.Weather" })
local weatherOk = true
for _, r in Map.Regions do
	local kind = Weather.get(r.id)
	if not WeatherConfig.Regions[r.id] or not WeatherConfig.Kinds[kind] then
		weatherOk = false
		print("WARN weather missing for region", r.id, kind)
	end
end
Weather.force("desert", "dust", 60)
if Weather.get("desert") ~= "dust" then weatherOk = false print("WARN weather force did not stick") end
print("weather", weatherOk and "ok" or "WRONG")

-- Region events: each one drops its bales near its region's fields, off the roads, with the Prices boost.
local RegionEvents = require({ __path = "Services.RegionEvents" })
local Prices = require({ __path = "Shared.Config.Prices" })
local WorldShapeE = require({ __path = "Services.WorldShape" })
local eventsOk = true
for _, e in RegionEvents.List do
	local reward = Prices.RegionEvents[e.id]
	local dropped = RegionEvents.run(e.id, 1)
	local n, onRoad = 0, 0
	for b in dropped do
		n += 1
		local d = WorldShapeE.nearestRoad(b.spawnPosition.X, b.spawnPosition.Z)
		if d and d < 6 then onRoad += 1 end
		if b.body:GetAttribute("NeedleBoost") ~= reward.boost then eventsOk = false end
	end
	if n < reward.bales * 0.6 or onRoad > 0 then
		eventsOk = false
		print("WARN event", e.id, "dropped", n, "of", reward.bales, "on road", onRoad)
	end
	print(("event %-14s %2d bales"):format(e.id, n))
end
RegionEvents.finish()
print("events", eventsOk and "ok" or "WRONG")

-- Wilds: the four secrets exist, the crater is hot, the Ghost Road holds only at night.
local Wilds = require({ __path = "Services.Wilds" })
local wildsOk = true
for _, id in { "ember_cache", "captains_lantern", "geode_heart", "lost_kite" } do
	if not Wilds.Secrets[id] or not Prices.Secrets[id] then
		wildsOk = false
		print("WARN secret missing", id)
	end
end
local ember = Wilds.Secrets.ember_cache
if ember and not Wilds.inHeat(ember.part.Position) then
	wildsOk = false
	print("WARN the Ember Cache is outside the crater's heat", ember.part.Position)
end
local quarry = Vector3.new(740, 30, -1300)
if Wilds.inHeat(quarry) then wildsOk = false print("WARN heat reaches the quarry") end
Lighting.ClockTime = 0
Wilds.refreshGhost()
if not Wilds.ghostSolid() then wildsOk = false print("WARN the Ghost Road is not solid at midnight") end
print("wilds", wildsOk and "ok" or "WRONG")

-- Discoveries: every landmark is found standing on it, every region standing in its middle, and nothing in Meadow.
local Discoveries = require({ __path = "Services.Discoveries" })
local discOk = true
local function finds(position, id)
	for _, got in Discoveries.at(position) do
		if got == id then return true end
	end
	return false
end
for _, entry in Discoveries.all() do
	local p
	if entry.kind == "landmark" then
		p = Vector3.new(entry.at.X, 20, entry.at.Y)
	else
		for _, r in Map.Regions do
			if r.id == entry.id then p = Vector3.new(r.center.X, WorldShapeE.heightAt(r.center.X, r.center.Y) + 3, r.center.Y) end
		end
	end
	if p and not finds(p, entry.id) then
		discOk = false
		print("WARN discovery not found where it stands", entry.id)
	end
end
if #Discoveries.at(Vector3.new(0, 5, 0)) > 0 then discOk = false print("WARN Meadow counts as a discovery") end
print("discoveries", #Discoveries.all(), discOk and "ok" or "WRONG")

-- Part budget: the whole map's share of the 40,000-part Workspace budget (Main.server.luau) is 12,000.
local mapParts = 0
for _, d in workspace:GetDescendants() do
	if d:IsA("BasePart") then mapParts += 1 end
end
print("map parts", mapParts, mapParts <= 12000 and "within 12000" or "WARN over the map's 12000 share")
