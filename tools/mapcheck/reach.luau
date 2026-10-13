-- Reachability (backlog Map #16): can a Rusty Pickup towing a Medium Trailer get everywhere from spawn?
-- Runs after check.luau has built the map. Prints REACH lines; a WARN for anything out of reach, a road too narrow
-- or too steep, or a field / secret / landmark underwater or inside rock.
local RMap = require({ __path = "Shared.Config.WorldMap" })
local RShape = require({ __path = "Services.WorldShape" })
local RRegions = require({ __path = "Services.Regions" })
local RWilds = require({ __path = "Services.Wilds" })

local COMBO_WIDTH = 10.9 -- the widest part of the pickup (its bed); the medium trailer is narrower
local COMBO_MARGIN = 2 -- studs to spare on a lane
local OFFROAD_SLOPE = 0.45 -- rise per stud a pickup with a trailer can still pull up off-road
local OFFROAD_REACH = 70 -- a field this far from its road is too far to back a trailer to
local WALK = 260 -- a landmark may be a short walk or climb from where the truck parks

local problems = 0
local function warn(...)
	problems += 1
	print("WARN reach", ...)
end

-- Nodes: "meadow", "highway", "sky", "road:<i>", "flat:<name>". Edges where they touch.
local edges = {}
local function link(a, b)
	edges[a] = edges[a] or {}
	edges[b] = edges[b] or {}
	edges[a][b] = true
	edges[b][a] = true
end
local function touches(p, i)
	-- Which nodes does this point (a road end) sit on?
	local hit = {}
	if RShape.meadowDistance(p.X, p.Y) < 4 or RShape.inMeadow(p.X, p.Y) then
		table.insert(hit, "meadow")
	end
	if RShape.highwayDistance(p.X, p.Y) < RMap.Highway.width then
		table.insert(hit, "highway")
	end
	for _, zone in RMap.Flat do
		if RShape.rectDistance(p.X, p.Y, zone.min, zone.max) <= 2 then
			table.insert(hit, "flat:" .. zone.name)
		end
	end
	for j, road in RMap.Roads do
		if j ~= i then
			for k = 1, #road.points - 1 do
				local a, b = road.points[k], road.points[k + 1]
				if RShape.segment(p.X, p.Y, a.X, a.Y, b.X, b.Y) < 4 then
					table.insert(hit, "road:" .. j)
					break
				end
			end
		end
	end
	return hit
end
for i, road in RMap.Roads do
	-- A road links to whatever any of its points touch (ends usually, but a flat it runs through counts too).
	for _, p in road.points do
		for _, node in touches(p, i) do
			link("road:" .. i, node)
		end
	end
end
-- Ferries join the flat zones (ports) their piers stand in; the zeppelin joins its field to Sky Island.
local function flatAt(p)
	local best, bestD = nil, math.huge
	for _, zone in RMap.Flat do
		local d = RShape.rectDistance(p.X, p.Y, zone.min, zone.max)
		if d < bestD then
			best, bestD = zone, d
		end
	end
	return best and bestD < 30 and "flat:" .. best.name or nil
end
for _, route in RMap.Ferry.Routes do
	local a, b = flatAt(route.a.shore), flatAt(route.b.shore)
	if not a or not b then
		warn("ferry has no port flat at a pier", route.name, a, b)
	else
		link(a, b)
	end
end
local zf = flatAt(Vector2.new(RMap.Zeppelin.a.pos.X, RMap.Zeppelin.a.pos.Z))
if zf then
	link(zf, "sky")
else
	warn("zeppelin field is not a flat zone")
end

-- Everything reachable from spawn (Meadow).
local reached = { meadow = true }
local queue = { "meadow" }
while #queue > 0 do
	local node = table.remove(queue, 1)
	for other in edges[node] or {} do
		if not reached[other] then
			reached[other] = true
			table.insert(queue, other)
		end
	end
end
local roadsReached = 0
for i, road in RMap.Roads do
	if reached["road:" .. i] then
		roadsReached += 1
	else
		warn("road not reachable from Meadow", road.name)
	end
end
if not reached.highway then
	warn("the Longstitch Highway is not reachable")
end
if not reached.sky then
	warn("Sky Island is not reachable")
end

-- Lanes wide enough, and grades a loaded pickup and trailer can climb.
if RMap.RoadWidth < COMBO_WIDTH + COMBO_MARGIN then
	warn("roads too narrow", RMap.RoadWidth)
end
if RMap.Highway.width < COMBO_WIDTH + COMBO_MARGIN then
	warn("highway too narrow", RMap.Highway.width)
end
if RMap.Ferry.Width / 3 < COMBO_WIDTH + COMBO_MARGIN then
	warn("ferry lanes too narrow", RMap.Ferry.Width / 3)
end
local steepest, steepAt = 0, nil
for _, road in RMap.Roads do
	for k = 1, #road.points - 1 do
		local a, b = road.points[k], road.points[k + 1]
		local steps = math.floor((b - a).Magnitude / 8)
		local last = nil
		for s = 0, steps do
			local p = a:Lerp(b, s / math.max(steps, 1))
			if not RShape.inMeadow(p.X, p.Y) then
				local _, h = RShape.nearestRoad(p.X, p.Y)
				if h and last then
					local grade = math.abs(h - last.h) / math.max(0.1, (p - last.p).Magnitude)
					if grade > steepest then
						steepest, steepAt = grade, ("%s at (%d, %d)"):format(road.name, p.X, p.Y)
					end
				end
				last = h and { h = h, p = p } or nil
			else
				last = nil
			end
		end
	end
end
if steepest > RMap.MaxGrade + 0.06 then
	warn(("steepest road %.2f at %s"):format(steepest, steepAt))
end

-- Nearest point on any reachable road to (x, z), with that road's index.
local function nearestReachedRoad(x, z)
	local best, bestP, bestI = math.huge, nil, nil
	for i, road in RMap.Roads do
		if reached["road:" .. i] then
			for k = 1, #road.points - 1 do
				local a, b = road.points[k], road.points[k + 1]
				local d, t = RShape.segment(x, z, a.X, a.Y, b.X, b.Y)
				if d < best then
					best, bestP, bestI = d, a:Lerp(b, t), i
				end
			end
		end
	end
	return best, bestP, bestI
end

-- Off-road from the road to a point: dry, and never steeper than the pickup can pull.
local function driveTo(target)
	local d, from = nearestReachedRoad(target.X, target.Y)
	if not from then
		return false, "no road"
	end
	if d > OFFROAD_REACH then
		return false, ("%.0f studs from a road"):format(d)
	end
	local steps = math.max(1, math.floor(d / 4))
	local lastH = nil
	for s = 0, steps do
		local p = from:Lerp(target, s / steps)
		local h, water = RShape.column(p.X, p.Y)
		if water and water > h + 1.5 then
			return false, ("water %.1f deep at (%d, %d)"):format(water - h, p.X, p.Y)
		end
		if lastH and math.abs(h - lastH) / (d / steps) > OFFROAD_SLOPE then
			return false, ("slope %.2f at (%d, %d)"):format(math.abs(h - lastH) / (d / steps), p.X, p.Y)
		end
		lastH = h
	end
	return true
end

local perRegion = {}
for _, entry in RRegions.fields do
	perRegion[entry.region] = (perRegion[entry.region] or 0) + 1
end
for _, r in RMap.Regions do
	if not perRegion[r.name] and r.id ~= "spindle" then -- the Spindle's hay is the Crystal Cave's
		warn("region has no hay field", r.name)
	end
end

-- Hay fields: drive up to every one (the cave field from the cave mouth, Sky Island's by zeppelin).
local fieldsOk, fieldsBad = 0, 0
for _, entry in RRegions.fields do
	local c = entry.center
	if entry.region == "Sky Island" then
		if reached.sky then fieldsOk += 1 else fieldsBad += 1 warn("Sky Island field unreachable") end
	elseif entry.region == "Crystal Cave" then
		local ok, why = driveTo(Vector2.new(RMap.Cave.mouth.X, RMap.Cave.mouth.Z))
		if ok then fieldsOk += 1 else fieldsBad += 1 warn("cave mouth", why) end
	else
		local h, water = RShape.column(c.X, c.Z)
		if water and water > h + 0.5 then
			fieldsBad += 1
			warn("field underwater", entry.region, c)
		elseif c.Y < h - 2 then
			fieldsBad += 1
			warn("field inside the ground", entry.region, c, h)
		else
			local ok, why = driveTo(Vector2.new(c.X, c.Z))
			if ok then fieldsOk += 1 else fieldsBad += 1 warn("field", entry.region, ("(%d, %d)"):format(c.X, c.Z), why) end
		end
	end
end

-- Landmark discoveries a truck can reach (the Graveyard of Ships is seen from the ferry, Ghost Isle is the night
-- road's end, the crater rim is a climb on foot).
local ON_FOOT = { graveyard_of_ships = true, ghost_isle = true, crater_rim = true, spindle_door = false }
local landmarksOk = 0
for _, d in RMap.Discoveries do
	local at = d.at
	if d.flat then
		for _, zone in RMap.Flat do
			if zone.name == d.flat then at = (zone.min + zone.max) / 2 end
		end
	end
	if at and not ON_FOOT[d.id] then
		local _, water = RShape.column(at.X, at.Y)
		local dist = nearestReachedRoad(at.X, at.Y)
		if water and d.id ~= "mirror_lake" then
			warn("landmark underwater", d.id)
		elseif dist > d.radius + WALK then
			warn("landmark far from a road", d.id, ("%.0f"):format(dist))
		else
			landmarksOk += 1
		end
	end
end

-- Quest markers out on the isles (Config/Quests Spots with a world position): a walk from a reachable road, and dry.
local QuestConfig = require({ __path = "Shared.Config.Quests" })
local CLIMBS = { volcano_crater = true, snow_door = true } -- meant to be climbs: up the crater, up the ridge
local questOk, questWet = 0, {}
for id, spot in QuestConfig.Spots do
	local at = spot.world
	if typeof(at) == "Vector2" then
		local h, water = RShape.column(at.X, at.Y)
		local dist = nearestReachedRoad(at.X, at.Y)
		if dist > WALK and not CLIMBS[id] then
			warn("quest marker far from a road", id, ("%.0f"):format(dist))
		elseif water and water > h + 1.5 then
			table.insert(questWet, id) -- may be meant (wrecks); listed, not failed
			questOk += 1
		else
			questOk += 1
		end
	end
end
print("REACH quest markers", questOk, #questWet > 0 and ("in water (by design?): " .. table.concat(questWet, ", ")) or "all dry")

-- Turns: no road bends harder than a pickup and trailer can follow at a junction-like corner.
for _, road in RMap.Roads do
	for k = 2, #road.points - 1 do
		local a = (road.points[k] - road.points[k - 1]).Unit
		local b = (road.points[k + 1] - road.points[k]).Unit
		local bend = math.deg(math.acos(math.clamp(a:Dot(b), -1, 1)))
		if bend > 100 then
			warn(("%s bends %d degrees at (%d, %d)"):format(road.name, bend, road.points[k].X, road.points[k].Y))
		end
	end
end

-- Secrets above water and out of the rock (the cave's and the sky's are in places of their own).
for id, s in RWilds.Secrets do
	if id ~= "geode_heart" and id ~= "lost_kite" and id ~= "captains_lantern" then
		local p = s.part.Position
		local h, water = RShape.column(p.X, p.Z)
		if water and water > p.Y then
			warn("secret underwater", id)
		elseif p.Y < h - 1 then
			warn("secret inside the rock", id, p.Y, h)
		end
	end
end

print(("REACH roads %d/%d, highway %s, sky %s, fields %d ok %d bad, landmarks %d, steepest road %.3f; %s"):format(
	roadsReached, #RMap.Roads, tostring(reached.highway), tostring(reached.sky), fieldsOk, fieldsBad, landmarksOk, steepest,
	problems == 0 and "ok" or (problems .. " problems")))
