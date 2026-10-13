--!nonstrict
--!native
-- Meadow Farm terrain, written by script. Rolling grass hills, flat ground under every building, dirt roads, a pond,
-- and tall hills around the edge. The same seed always gives the same land.
--
-- Load time: pressing Play builds it in about a second. To skip even that, bake it once in Studio's edit mode
-- (command bar):  require(game.ServerScriptService.Server.Services.MeadowTerrain).generate()
-- then save the place. Play sees the baked terrain (Terrain's MeadowVersion attribute) and leaves it alone.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Meadow = require(Shared.Config.Meadow)
local Rustic = require(Shared.Config.Rustic)

local MeadowTerrain = {}

local RES = 4 -- voxel size in studs
local CHUNK = 64 -- voxels per side written at once
local SEED = Meadow.Seed * 17.31

-- Looked up once: indexing Enum in the voxel loop would cost more than the rest of the work.
local AIR = Enum.Material.Air
local GROUND = Enum.Material.Ground
local WATER = Enum.Material.Water
-- Never Enum.Material.Grass: only Grass grows the tall decoration blades, and Terrain.Decoration cannot be turned
-- off from a script or Rojo (it is not scriptable). The meadow is LeafyGrass with darker Moss patches instead.
local GRASS = Enum.Material.LeafyGrass
local LEAFY = Enum.Material.Moss
local ROCK = Enum.Material.Rock
local SAND = Enum.Material.Sand
local MUD = Enum.Material.Mud

local function smoothstep(edge0, edge1, x)
	local t = math.clamp((x - edge0) / (edge1 - edge0), 0, 1)
	return t * t * (3 - 2 * t)
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

-- Distance from a point to a rect on the ground (0 inside).
local function rectDistance(x, z, min, max)
	local dx = math.max(min.X - x, 0, x - max.X)
	local dz = math.max(min.Y - z, 0, z - max.Y)
	return math.sqrt(dx * dx + dz * dz)
end

local function segmentDistance(x, z, a, b)
	local abx, abz = b.X - a.X, b.Y - a.Y
	local t = math.clamp(((x - a.X) * abx + (z - a.Y) * abz) / (abx * abx + abz * abz), 0, 1)
	local dx, dz = x - (a.X + abx * t), z - (a.Y + abz * t)
	return math.sqrt(dx * dx + dz * dz)
end

-- Distance to the nearest road's center line.
function MeadowTerrain.roadDistance(x, z)
	local best = math.huge
	for _, road in Meadow.Roads do
		for i = 1, #road.points - 1 do
			best = math.min(best, segmentDistance(x, z, road.points[i], road.points[i + 1]))
		end
	end
	return best
end

local function noise(x, z, scale, salt)
	return math.noise(x / scale + SEED + salt * 3.7, z / scale - SEED + salt * 1.9, salt * 0.61 + 0.5)
end

-- How strongly the ground here is pulled flat to height 0 (1 = fully flat).
local function flatness(x, z)
	local w = 0
	for _, zone in Meadow.Flat do
		local d = rectDistance(x, z, zone.min, zone.max)
		w = math.max(w, 1 - smoothstep(0, zone.blend, d))
	end
	local road = MeadowTerrain.roadDistance(x, z)
	w = math.max(w, 1 - smoothstep(Meadow.RoadWidth / 2, Meadow.RoadWidth / 2 + 26, road))
	return w
end

-- Ground height at a point. Deterministic, so anything can ask without raycasting.
function MeadowTerrain.heightAt(x, z)
	local h = Meadow.BaseHeight
	for i, hill in Meadow.Hills do
		h += hill.amplitude * noise(x, z, hill.scale, i)
	end
	local edge = smoothstep(Meadow.EdgeStart, Meadow.HalfSize - 12, math.max(math.abs(x), math.abs(z)))
	h += edge * (Meadow.EdgeHeight + 18 * noise(x, z, 60, 9))

	h = lerp(h, 0, flatness(x, z))

	-- The pond: level ground around it, then a bowl that holds water.
	local pond = Meadow.Pond
	local d = math.sqrt((x - pond.center.X) ^ 2 + (z - pond.center.Y) ^ 2)
	h = lerp(h, 1, 1 - smoothstep(pond.radius, pond.radius + 50, d))
	h -= pond.depth * (1 - smoothstep(pond.radius * 0.35, pond.radius + 6, d))
	return math.min(h, Meadow.Top - 2)
end

local function inPond(x, z)
	local pond = Meadow.Pond
	return (x - pond.center.X) ^ 2 + (z - pond.center.Y) ^ 2 < (pond.radius + 8) ^ 2
end

-- Surface material for a column, from its height and the slope around it.
local function surfaceMaterial(x, z, h, slope)
	if MeadowTerrain.roadDistance(x, z) < Meadow.RoadWidth / 2 + noise(x, z, 9, 4) * 1.5 then
		return GROUND
	end
	if inPond(x, z) and h < Meadow.Pond.waterLevel + 1.2 then
		return h < Meadow.Pond.waterLevel - 2 and MUD or SAND
	end
	if slope > 0.9 or (h > 34 and noise(x, z, 30, 6) > 0.1) then
		return ROCK
	end
	if noise(x, z, 45, 5) > 0.22 then
		return LEAFY
	end
	return GRASS
end

local function setColors(terrain)
	-- Roblox's decoration grass grows knee-high on the Grass material and hides bales, pads and paths. Cut it short
	-- and switch it off; each in its own pcall, since a place may refuse script writes to either.
	pcall(function()
		terrain.GrassLength = 0.1
	end)
	pcall(function()
		terrain.Decoration = false
	end)
	terrain:SetMaterialColor(Enum.Material.Grass, Rustic.Grass)
	terrain:SetMaterialColor(Enum.Material.LeafyGrass, Rustic.Grass)
	terrain:SetMaterialColor(Enum.Material.Moss, Rustic.LeafyGrass)
	terrain:SetMaterialColor(Enum.Material.Ground, Rustic.Dirt)
	terrain:SetMaterialColor(Enum.Material.Mud, Rustic.Mud)
	terrain:SetMaterialColor(Enum.Material.Sand, Rustic.Sand)
	terrain:SetMaterialColor(Enum.Material.Rock, Rustic.Rock)
	terrain.WaterColor = Rustic.Water
	terrain.WaterTransparency = 0.6
	terrain.WaterWaveSize = 0.05
end

function MeadowTerrain.isBuilt()
	return Workspace.Terrain:GetAttribute("MeadowVersion") == Meadow.Version
end

-- Writes the whole biome. Yields between chunks while the game runs so the server never freezes.
function MeadowTerrain.generate()
	local terrain = Workspace.Terrain
	local started = os.clock()
	local half = Meadow.HalfSize
	local columns = half * 2 // RES
	local bottom = Meadow.Bottom
	local water = Meadow.Pond.waterLevel

	-- Heights at the center of every column first, so slopes can use the neighbors.
	local heights = table.create(columns)
	for i = 1, columns do
		local row = table.create(columns)
		local x = -half + (i - 0.5) * RES
		for k = 1, columns do
			row[k] = MeadowTerrain.heightAt(x, -half + (k - 0.5) * RES)
		end
		heights[i] = row
	end

	-- Chunks nearest base camp go first, so the spawn has ground under it right away.
	local chunks = {}
	for ci = 0, columns // CHUNK - 1 do
		for ck = 0, columns // CHUNK - 1 do
			table.insert(chunks, { ci, ck })
		end
	end
	local mid = columns / CHUNK / 2 - 0.5
	table.sort(chunks, function(a, b)
		return (a[1] - mid) ^ 2 + (a[2] - mid) ^ 2 < (b[1] - mid) ^ 2 + (b[2] - mid) ^ 2
	end)

	-- Start clean, so an older layout never leaves hills floating above the new one.
	terrain:Clear()

	for _, chunk in chunks do
		local i0, k0 = chunk[1] * CHUNK, chunk[2] * CHUNK

		-- Only write the layers this chunk needs: a shell 3 voxels thick under its lowest ground, up to its highest
		-- ground or the pond surface. Air above is already empty, which keeps the write small and quick.
		local lowest, highest = math.huge, -math.huge
		for di = 1, CHUNK do
			local row = heights[i0 + di]
			for dk = 1, CHUNK do
				local h = row[k0 + dk]
				lowest = math.min(lowest, h)
				highest = math.max(highest, h)
			end
		end
		highest = math.max(highest, water)
		local first = math.max(1, (lowest - bottom) // RES - 2)
		local last = math.min((Meadow.Top - bottom) // RES, (highest - bottom) // RES + 1)
		local layers = last - first + 1
		local base = bottom + (first - 1) * RES

		local materials = table.create(CHUNK)
		local occupancy = table.create(CHUNK)
		for di = 1, CHUNK do
			local i = i0 + di
			local x = -half + (i - 0.5) * RES
			local matX = table.create(layers)
			local occX = table.create(layers)
			for j = 1, layers do
				matX[j] = table.create(CHUNK)
				occX[j] = table.create(CHUNK)
			end
			for dk = 1, CHUNK do
				local k = k0 + dk
				local z = -half + (k - 0.5) * RES
				local h = heights[i][k]
				local hx = heights[math.clamp(i + 1, 1, columns)][k] - heights[math.clamp(i - 1, 1, columns)][k]
				local hz = heights[i][math.clamp(k + 1, 1, columns)] - heights[i][math.clamp(k - 1, 1, columns)]
				local slope = math.sqrt(hx * hx + hz * hz) / (RES * 2)
				local top = surfaceMaterial(x, z, h, slope)
				local wet = inPond(x, z)
				for j = 1, layers do
					local y0 = base + (j - 1) * RES
					local fill = math.clamp((h - y0) / RES, 0, 1)
					local material, occ = AIR, 0
					if fill > 0 then
						material = (h - y0 > RES * 3) and GROUND or top
						occ = fill
					elseif wet and y0 < water then
						material = WATER
						occ = math.clamp((water - y0) / RES, 0, 1)
					end
					matX[j][dk] = material
					occX[j][dk] = occ
				end
			end
			materials[di] = matX
			occupancy[di] = occX
		end
		local low = Vector3.new(-half + i0 * RES, base, -half + k0 * RES)
		local region = Region3.new(low, low + Vector3.new(CHUNK * RES, layers * RES, CHUNK * RES))
		terrain:WriteVoxels(region, RES, materials, occupancy)
		if RunService:IsRunning() then
			task.wait()
		end
	end

	setColors(terrain)
	terrain:SetAttribute("MeadowVersion", Meadow.Version)
	print(("[Needlewood] Meadow terrain written in %.1fs"):format(os.clock() - started))
end

-- Builds the terrain unless this place already has the current version baked in.
function MeadowTerrain.ensure()
	if MeadowTerrain.isBuilt() then
		setColors(Workspace.Terrain)
		return
	end
	MeadowTerrain.generate()
end

-- The real ground height under a point (terrain surface), falling back to the formula.
function MeadowTerrain.groundAt(x, z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { Workspace.Terrain }
	params.IgnoreWater = true
	local hit = Workspace:Raycast(Vector3.new(x, Meadow.Top + 10, z), Vector3.new(0, -(Meadow.Top - Meadow.Bottom + 20), 0), params)
	if hit then
		return hit.Position.Y, hit.Normal, hit.Material
	end
	return MeadowTerrain.heightAt(x, z), Vector3.yAxis, nil
end

return MeadowTerrain
