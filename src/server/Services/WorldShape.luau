--!nonstrict
--!native
-- The shape of the Stitched Isles outside Meadow Farm, as plain math: ground height, water and surface material for
-- any point. WorldTerrain writes it into voxels and Regions places trees and buildings on it, so both always agree.
-- Pure functions of Config/WorldMap.luau and the Meadow edge, so the same seed always gives the same islands.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Map = require(Shared.Config.WorldMap)
local Meadow = require(Shared.Config.Meadow)
local MeadowTerrain = require(script.Parent.MeadowTerrain)

local WorldShape = {}

local HALF = Meadow.HalfSize
local SEED = Map.Seed * 13.7
local SEA = Map.SeaLevel
local ROAD_HALF = Map.RoadWidth / 2
local ROAD_BLEND = 22 -- how far past the road's edge the land takes to rise or fall back
local CELL = 64 -- road lookup grid

local function smoothstep(edge0, edge1, x)
	local t = math.clamp((x - edge0) / (edge1 - edge0), 0, 1)
	return t * t * (3 - 2 * t)
end
WorldShape.smoothstep = smoothstep

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function noise(x, z, scale, salt)
	return math.noise(x / scale + SEED + salt * 3.1, z / scale - SEED + salt * 2.3, salt * 0.37 + 0.5)
end
WorldShape.noise = noise

local function rectDistance(x, z, min, max)
	local dx = math.max(min.X - x, 0, x - max.X)
	local dz = math.max(min.Y - z, 0, z - max.Y)
	return math.sqrt(dx * dx + dz * dz)
end
WorldShape.rectDistance = rectDistance

-- Distance from a point to segment ab, and how far along it (0..1) the nearest point is.
local function segment(x, z, ax, az, bx, bz)
	local abx, abz = bx - ax, bz - az
	local len2 = abx * abx + abz * abz
	local t = len2 > 0 and math.clamp(((x - ax) * abx + (z - az) * abz) / len2, 0, 1) or 0
	local dx, dz = x - (ax + abx * t), z - (az + abz * t)
	return math.sqrt(dx * dx + dz * dz), t
end
WorldShape.segment = segment

-- Distance outside Meadow's square (0 on or inside it).
local function meadowDistance(x, z)
	local dx = math.max(math.abs(x) - HALF, 0)
	local dz = math.max(math.abs(z) - HALF, 0)
	return math.sqrt(dx * dx + dz * dz)
end
WorldShape.meadowDistance = meadowDistance

function WorldShape.inMeadow(x, z)
	return math.abs(x) < HALF and math.abs(z) < HALF
end

-- Regions ---------------------------------------------------------------------------------------------------------

local regions = {}
for i, def in Map.Regions do
	local r = table.clone(def)
	r.index = i
	r.salt = i * 1.7
	r.cx, r.cz = def.center.X, def.center.Y
	r.rx, r.rz = def.radius.X, def.radius.Y
	-- Past 1.45 radii a region has no say at all, so most points only ask two or three regions.
	r.reach = 1.45
	regions[i] = r
end
WorldShape.regions = regions

function WorldShape.region(id)
	for _, r in regions do
		if r.id == id then
			return r
		end
	end
	return nil
end

-- How far inside a region's oval a point is: 1 at its center, 0 on its coast, negative outside. The coast wobbles.
local function inside(r, x, z)
	local dx, dz = (x - r.cx) / r.rx, (z - r.cz) / r.rz
	local d2 = dx * dx + dz * dz
	if d2 > r.reach * r.reach then
		return -1
	end
	local d = math.sqrt(d2) * (1 + 0.10 * noise(x, z, 260, r.salt) + 0.05 * noise(x, z, 70, r.salt + 1))
	local value = 1 - d
	if r.islets then
		-- Channels of sea break the keys into a chain of islets.
		local channel = math.abs(noise(x, z, 150, r.salt + 4))
		value -= math.max(0, 0.12 - channel) * 2.6
	end
	return value
end

local function peakHeight(peak, x, z)
	local dx, dz = x - peak.center.X, z - peak.center.Y
	local dist = math.sqrt(dx * dx + dz * dz)
	if dist >= peak.radius then
		return 0
	end
	local shape = (1 - dist / peak.radius) ^ peak.power
	local h = peak.height * shape
	if peak.crater and dist < peak.crater then
		local rim = peak.height * (1 - peak.crater / peak.radius) ^ peak.power
		local k = dist / peak.crater
		h = rim + 6 - peak.craterDepth * (1 - k * k)
	end
	return h
end

local function regionHeight(r, x, z)
	local h = r.base
	for i, hill in r.hills do
		h += hill[1] * noise(x, z, hill[2], r.salt + i)
	end
	if r.peak then
		h += peakHeight(r.peak, x, z)
		-- A rough, ridged face on big mountains.
		h += 10 * math.abs(noise(x, z, 40, r.salt + 7)) * smoothstep(0, r.peak.radius, r.peak.radius - math.sqrt((x - r.peak.center.X) ^ 2 + (z - r.peak.center.Y) ^ 2))
	end
	if r.dunes then
		-- Long dune ridges that run north-south.
		local ridge = 1 - math.abs(noise(x / 2.2, z, r.dunes.scale, r.salt + 5))
		h += r.dunes.amplitude * ridge * ridge
	end
	return h
end

-- Roads -----------------------------------------------------------------------------------------------------------
-- Each road is cut into short pieces with a height at each end. The heights follow the land, smoothed, never steeper
-- than MaxGrade, and never under the sea (over water a road becomes a causeway).

local roadPieces = {} -- { ax, az, bx, bz, ha, hb, road }
local roadGrid = {} -- cell key -> list of pieces

local function gridKey(cx, cz)
	return cx * 65536 + cz
end

-- Land height before roads are cut in (used to lay the roads themselves).
local baseHeight -- forward declared, set below

local function addPiece(piece)
	table.insert(roadPieces, piece)
	local reach = ROAD_HALF + ROAD_BLEND + 4
	local x0 = math.floor((math.min(piece[1], piece[3]) - reach) / CELL)
	local x1 = math.floor((math.max(piece[1], piece[3]) + reach) / CELL)
	local z0 = math.floor((math.min(piece[2], piece[4]) - reach) / CELL)
	local z1 = math.floor((math.max(piece[2], piece[4]) + reach) / CELL)
	for cx = x0, x1 do
		for cz = z0, z1 do
			local key = gridKey(cx, cz)
			local list = roadGrid[key]
			if not list then
				list = {}
				roadGrid[key] = list
			end
			table.insert(list, piece)
		end
	end
end

-- Nearest road piece to a point: distance, road height there, the road's name, and the nearest point on its center
-- line (x, z). nil when none is close.
local function nearestRoad(x, z)
	local list = roadGrid[gridKey(math.floor(x / CELL), math.floor(z / CELL))]
	if not list then
		return nil
	end
	local best, bestH, bestRoad, bestX, bestZ = math.huge, 0, nil, x, z
	for _, p in list do
		local d, t = segment(x, z, p[1], p[2], p[3], p[4])
		if d < best then
			best, bestH, bestRoad = d, lerp(p[5], p[6], t), p[7]
			bestX, bestZ = lerp(p[1], p[3], t), lerp(p[2], p[4], t)
		end
	end
	return best, bestH, bestRoad, bestX, bestZ
end
WorldShape.nearestRoad = nearestRoad

local function layRoads()
	local STEP = 8
	local laid = {} -- earlier roads' samples, for joining junctions
	for _, road in Map.Roads do
		-- Sample points along the road.
		local samples = {}
		for i = 1, #road.points - 1 do
			local a, b = road.points[i], road.points[i + 1]
			local n = math.max(1, math.ceil((b - a).Magnitude / STEP))
			for k = (i == 1 and 0 or 1), n do
				local p = a:Lerp(b, k / n)
				table.insert(samples, { x = p.X, z = p.Y, h = 0, pin = nil :: number? })
			end
		end
		for _, s in samples do
			-- Ports, plazas and the highway ends are flat zones: the road arrives at their height, so a truck rolls
			-- straight onto a pier or the highway deck with no step.
			s.h = math.max(WorldShape.applyFlats(s.x, s.z, baseHeight(s.x, s.z)), SEA + 2.5)
			for _, zone in Map.Flat do
				if rectDistance(s.x, s.z, zone.min, zone.max) <= 0 then
					s.pin = zone.height
				end
			end
			-- Meadow's own roads arrive flat at height 0 at its edge.
			if meadowDistance(s.x, s.z) < 1 then
				s.pin = 0
			end
			-- A road that starts or ends on an earlier road joins it at that road's height.
			for _, other in laid do
				if (other.x - s.x) ^ 2 + (other.z - s.z) ^ 2 < 36 then
					s.pin = other.h
					break
				end
			end
		end
		-- Smooth the heights, then keep the grade gentle in both directions.
		local n = #samples
		for _ = 1, 4 do
			local smoothed = table.create(n)
			for i = 1, n do
				local sum, count = 0, 0
				for k = math.max(1, i - 8), math.min(n, i + 8) do
					sum += samples[k].h
					count += 1
				end
				smoothed[i] = sum / count
			end
			for i = 1, n do
				samples[i].h = samples[i].pin or math.max(smoothed[i], SEA + 2.5)
			end
		end
		local rise = Map.MaxGrade * STEP
		for i = 2, n do
			local s, prev = samples[i], samples[i - 1]
			if not s.pin then
				s.h = math.clamp(s.h, prev.h - rise, prev.h + rise)
			end
		end
		for i = n - 1, 1, -1 do
			local s, nxt = samples[i], samples[i + 1]
			if not s.pin then
				s.h = math.clamp(s.h, nxt.h - rise, nxt.h + rise)
			end
		end
		for i = 1, n - 1 do
			local a, b = samples[i], samples[i + 1]
			addPiece({ a.x, a.z, b.x, b.z, a.h, b.h, road.name })
		end
		for _, s in samples do
			table.insert(laid, s)
		end
	end
end

-- The highway deck height at an X along the Longstitch Highway (Config Highway.Profile).
function WorldShape.highwayY(x)
	local profile = Map.Highway.Profile
	if x <= profile[1][1] then
		return profile[1][2]
	end
	for i = 1, #profile - 1 do
		local a, b = profile[i], profile[i + 1]
		if x <= b[1] then
			return lerp(a[2], b[2], (x - a[1]) / (b[1] - a[1]))
		end
	end
	return profile[#profile][2]
end

-- Distance from the highway's center line, and the X along it.
function WorldShape.highwayDistance(x, z)
	local hw = Map.Highway
	local d, t = segment(x, z, hw.from.X, hw.from.Y, hw.to.X, hw.to.Y)
	return d, lerp(hw.from.X, hw.to.X, t)
end

-- Height ------------------------------------------------------------------------------------------------------------

-- How much land there is here (positive = land) and the land height, before roads and special features.
local UNION = 7 -- how readily neighboring regions merge into one coast (higher = sharper, more separate)

local function landShape(x, z)
	local sum, weight = 0, 0
	local union = 0
	local best, bestInside = nil, -math.huge

	-- Meadow counts as a region whose land reaches MeadowShore past its square, at its own edge height.
	local dm = meadowDistance(x, z)
	local meadowInside = 1 - dm / Map.MeadowShore
	if meadowInside > -0.4 then
		local edgeH = MeadowTerrain.heightAt(math.clamp(x, -HALF, HALF), math.clamp(z, -HALF, HALF))
		local w = (meadowInside + 0.4) ^ 2
		-- Away from the edge the meadow's hills settle down to gentle country.
		local h = lerp(edgeH, 10 + 6 * noise(x, z, 120, 0.3), smoothstep(0, Map.MeadowShore, dm))
		sum += h * w
		weight += w
		union += math.exp(UNION * meadowInside)
	end

	for _, r in regions do
		local v = inside(r, x, z)
		if v > -0.4 then
			local w = (v + 0.4) ^ 2
			sum += regionHeight(r, x, z) * w
			weight += w
			union += math.exp(UNION * v)
			if v > bestInside then
				best, bestInside = r, v
			end
		end
	end

	-- A soft union: two regions that nearly touch share one coast instead of leaving a thin strait between them.
	local landness = union > 0 and math.log(union) / UNION or -1
	landness += 0.04 * noise(x, z, 110, 21)

	local land = weight > 0 and sum / weight or 0
	-- The coast: land drops away under the sea as landness goes below zero.
	local coast = smoothstep(-0.07, 0.09, landness)
	local floor = Map.SeaFloor + 6 * noise(x, z, 90, 9)
	local h = lerp(floor, land, coast)

	-- Right at Meadow's square the ground meets its edge exactly.
	if dm < Map.MeadowBlend then
		local edgeH = MeadowTerrain.heightAt(math.clamp(x, -HALF, HALF), math.clamp(z, -HALF, HALF))
		h = lerp(edgeH, h, smoothstep(0, Map.MeadowBlend, dm))
	end
	return h, landness, best, bestInside, dm
end

local function applyFlats(x, z, h)
	local zoneMaterial = nil
	for _, zone in Map.Flat do
		local d = rectDistance(x, z, zone.min, zone.max)
		if d < zone.blend then
			local f = 1 - smoothstep(0, zone.blend, d)
			h = lerp(h, zone.height, f)
			if d <= 0 and zone.material then
				zoneMaterial = zone.material
			end
		end
	end
	return h, zoneMaterial
end
WorldShape.applyFlats = applyFlats

local function bowl(x, z, h, def)
	local d = math.sqrt((x - def.center.X) ^ 2 + (z - def.center.Y) ^ 2)
	if d < def.radius + 50 then
		-- Level shore, then a bowl that holds water.
		h = lerp(h, def.level + 1.5, 1 - smoothstep(def.radius, def.radius + 50, d))
		if d < def.radius + 6 then
			h = math.min(h, def.level + 1 - def.depth * (1 - smoothstep(def.radius * 0.3, def.radius + 6, d)))
		end
	end
	return h, d
end

baseHeight = function(x, z)
	local h = landShape(x, z)
	h = applyFlats(x, z, h)
	return h
end

-- Everything about one column of ground: height, the water surface over it (or nil), the surface material name and
-- the region it belongs to. slope is filled in by the caller when it has neighbors (WorldTerrain).
function WorldShape.column(x, z)
	local h, landness, region, _, dm = landShape(x, z)
	local material = nil
	local water = nil
	local h0

	h, material = applyFlats(x, z, h)

	-- Sea lanes stay deep so the ferries clear the bottom. They only deepen sea that is already there.
	for _, lane in Map.Channels do
		local d = segment(x, z, lane.from.X, lane.from.Y, lane.to.X, lane.to.Y)
		if d < lane.width / 2 + 40 and h < SEA - 2 then
			h = math.min(h, lerp(lane.depth, h, smoothstep(lane.width / 2, lane.width / 2 + 40, d)))
		end
	end

	-- Mirror Lake and the desert oasis.
	local ld
	h, ld = bowl(x, z, h, Map.Lake)
	if ld < Map.Lake.radius + 8 and h < Map.Lake.level then
		water = Map.Lake.level
	end
	local od
	h, od = bowl(x, z, h, Map.Oasis)
	if od < Map.Oasis.radius + 6 and h < Map.Oasis.level then
		water = Map.Oasis.level
	end

	-- Bog pools in the swamp.
	if region and region.pools and landness > 0.05 then
		local p = region.pools
		local n = noise(x, z, p.scale, region.salt + 11)
		if n < p.threshold then
			local deep = smoothstep(p.threshold, p.threshold - 0.15, n)
			h = math.min(h, lerp(h, p.level - 3, deep))
			if h < p.level then
				water = p.level
			end
		end
	end

	-- Roads cut and fill the land to their own height.
	h0 = h
	local roadD, roadH = nearestRoad(x, z)
	local onRoad = false
	if roadD and roadD < ROAD_HALF + ROAD_BLEND then
		h = lerp(h, roadH, 1 - smoothstep(ROAD_HALF, ROAD_HALF + ROAD_BLEND, roadD))
		onRoad = roadD < ROAD_HALF + noise(x, z, 9, 4) * 1.5
		if onRoad and water and h >= water then
			water = nil
		end
	end

	-- The Longstitch Highway is parts: keep the sea under its bridge, and dig a bed for the undersea tube.
	local hwD, hwX = WorldShape.highwayDistance(x, z)
	local tube = nil
	local hw = Map.Highway
	if hwD < hw.width / 2 + 6 and hwX > hw.Profile[2][1] and hwX < hw.Profile[#hw.Profile][1] - 20 then
		local deck = WorldShape.highwayY(hwX)
		if deck < SEA + 2 then
			-- Inside the tube is air; the sea starts above its roof.
			tube = { floor = deck - 1, roof = deck + hw.tubeTop + 1.5 }
			h = math.min(h, deck - 1.5)
		end
	end

	-- Sea over anything below sea level that isn't Meadow.
	if not water and h < SEA and dm > 0 then
		water = SEA
	end

	-- Surface material.
	if not material then
		if onRoad then
			material = "Ground"
		elseif water and h < water - 0.5 then
			material = (h < SEA - 14) and "Slate" or (region and region.materials.beach == "Mud" and "Mud" or "Sand")
		elseif not region or landness < -0.1 then
			material = h < SEA + 3 and "Sand" or "LeafyGrass"
		else
			local m = region.materials
			if h < SEA + 2.5 and landness < 0.2 then
				material = m.beach
			elseif region.snowLine and h > region.snowLine then
				material = noise(x, z, 30, 12) > 0.25 and "Glacier" or "Snow"
			elseif region.peak and region.peak.crater then
				local pd = math.sqrt((x - region.peak.center.X) ^ 2 + (z - region.peak.center.Y) ^ 2)
				if pd < region.peak.crater * 0.8 then
					material = "CrackedLava"
				elseif region.lavaRivers and pd < region.peak.radius * 0.95 and math.abs(noise(x, z, 60, 13)) < 0.025 then
					material = "CrackedLava"
				end
			end
			if not material then
				material = noise(x, z, 45, region.salt + 6) > 0.25 and m.alt or m.top
			end
		end
	end
	-- Grass blades only grow on the Grass material; nothing out here uses it, so the ground stays clear to see.
	if material == "Grass" then
		material = "LeafyGrass"
	end
	return h, water, material, region, tube, h0
end

-- Ground height at a point (roads and flats included).
function WorldShape.heightAt(x, z)
	if WorldShape.inMeadow(x, z) then
		return MeadowTerrain.heightAt(x, z)
	end
	local h = WorldShape.column(x, z)
	return h
end

-- The region a point belongs to (nil out at sea or in Meadow).
function WorldShape.regionAt(x, z)
	local _, landness, region = landShape(x, z)
	if landness < 0 then
		return nil
	end
	return region
end

-- The cliff material for steep ground at a point.
function WorldShape.cliffAt(region)
	return region and region.materials.cliff or "Rock"
end

layRoads()

return WorldShape
