--!nonstrict
--!native
-- Writes the Stitched Isles into terrain voxels: every region outside Meadow Farm, the sea between them, Sky Island
-- in the air and the cave under the Spindle. The shape itself is WorldShape.luau; this only turns it into voxels.
--
-- Load time: pressing Play writes the whole map in the background, nearest to Meadow first, so you can play while
-- the far islands appear. To skip that, bake it once in Studio's edit mode (command bar), after Meadow:
--   require(game.ServerScriptService.Server.Services.WorldTerrain).generate()
-- then save the place. Play sees the baked map (Terrain's WorldMapVersion attribute) and leaves it alone.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Map = require(Shared.Config.WorldMap)
local Meadow = require(Shared.Config.Meadow)
local WorldShape = require(script.Parent.WorldShape)

local WorldTerrain = {}

local RES = 4 -- voxel size in studs
local CHUNK = 64 -- voxels per side written at once (256 studs, so Meadow's square is exactly 4 x 4 chunks)
local BOTTOM = -48 -- lowest voxel layer written (below the deepest sea floor)
local HALF = Meadow.HalfSize

local AIR = Enum.Material.Air
local WATER = Enum.Material.Water

-- Material names in Config and WorldShape to Enum values, looked up once.
local materials = {}
local function material(name)
	local m = materials[name]
	if not m then
		m = Enum.Material[name]
		materials[name] = m
	end
	return m
end

local built = false -- set once this server has the map

local function setColors(terrain)
	for name, color in Map.Colors do
		pcall(function()
			terrain:SetMaterialColor(Enum.Material[name], color)
		end)
	end
end

-- One chunk of columns: compute the ground (with a border so slopes see their neighbors) and write the voxels.
local function writeChunk(terrain, x0, z0)
	local n = CHUNK + 2
	local hs, waters, mats, regions, tubes = table.create(n), table.create(n), table.create(n), table.create(n), table.create(n)
	for i = 1, n do
		local x = x0 + (i - 1.5) * RES
		local hr, wr, mr, rr, tr = table.create(n), table.create(n), table.create(n), table.create(n), table.create(n)
		for k = 1, n do
			local z = z0 + (k - 1.5) * RES
			local h, water, mat, region, tube
			if WorldShape.inMeadow(x, z) then
				-- Border columns that fall inside Meadow only feed the slope; they are never written.
				h = WorldShape.heightAt(x, z)
			else
				h, water, mat, region, tube = WorldShape.column(x, z)
			end
			hr[k], wr[k], mr[k], rr[k], tr[k] = h, water or false, mat or false, region or false, tube or false
		end
		hs[i], waters[i], mats[i], regions[i], tubes[i] = hr, wr, mr, rr, tr
	end

	-- Which layers this chunk needs: from a shell under its lowest ground up to its highest ground or water.
	local lowest, highest = math.huge, -math.huge
	for i = 2, n - 1 do
		for k = 2, n - 1 do
			local h = hs[i][k]
			lowest = math.min(lowest, h)
			highest = math.max(highest, h, waters[i][k] or -math.huge)
		end
	end
	local first = math.max(1, (lowest - BOTTOM) // RES - 2)
	local last = (highest - BOTTOM) // RES + 1
	local layers = last - first + 1
	local base = BOTTOM + (first - 1) * RES

	local matGrid = table.create(CHUNK)
	local occGrid = table.create(CHUNK)
	for di = 1, CHUNK do
		local i = di + 1
		local matX = table.create(layers)
		local occX = table.create(layers)
		for j = 1, layers do
			matX[j] = table.create(CHUNK, AIR)
			occX[j] = table.create(CHUNK, 0)
		end
		for dk = 1, CHUNK do
			local k = dk + 1
			local h = hs[i][k]
			local name = mats[i][k]
			if name then
				local water = waters[i][k]
				local tube = tubes[i][k]
				local region = regions[i][k]
				local hx = hs[i + 1][k] - hs[i - 1][k]
				local hz = hs[i][k + 1] - hs[i][k - 1]
				local slope = math.sqrt(hx * hx + hz * hz) / (RES * 2)
				-- Steep ground shows the region's rock, except on roads and under water.
				if slope > 0.9 and name ~= "Ground" and not (water and h < water) and name ~= "CrackedLava" then
					name = region and region.materials.cliff or "Rock"
				end
				local top = material(name)
				local deep = material(region and region.materials.cliff or "Ground")
				for j = 1, layers do
					local y0 = base + (j - 1) * RES
					local fill = (h - y0) / RES
					if fill > 0 then
						matX[j][dk] = (h - y0 > RES * 3) and deep or top
						occX[j][dk] = math.min(fill, 1)
					elseif tube and y0 + RES > tube.floor and y0 < tube.roof then
						-- The undersea tube's inside stays dry.
						continue
					elseif water and y0 < water then
						matX[j][dk] = WATER
						occX[j][dk] = math.clamp((water - y0) / RES, 0, 1)
					end
				end
			end
		end
		matGrid[di] = matX
		occGrid[di] = occX
	end
	local low = Vector3.new(x0, base, z0)
	terrain:WriteVoxels(Region3.new(low, low + Vector3.new(CHUNK * RES, layers * RES, CHUNK * RES)), RES, matGrid, occGrid)
end

-- Sky Island: a floating disc of land with a rounded underside, above Homestead.
local function writeSkyIsland(terrain)
	local sky = Map.SkyIsland
	local r = sky.radius + 24
	local x0 = math.floor((sky.center.X - r) / RES) * RES
	local z0 = math.floor((sky.center.Y - r) / RES) * RES
	local size = math.ceil(r * 2 / RES)
	local yBase = math.floor((sky.top - sky.thickness - 20) / RES) * RES
	local layers = math.ceil((sky.thickness + 50) / RES)
	local matGrid, occGrid = table.create(size), table.create(size)
	local grass, cloud, under = material("LeafyGrass"), material("Salt"), material("Limestone")
	for i = 1, size do
		local x = x0 + (i - 0.5) * RES
		local matX, occX = table.create(layers), table.create(layers)
		for j = 1, layers do
			matX[j] = table.create(size, AIR)
			occX[j] = table.create(size, 0)
		end
		for k = 1, size do
			local z = z0 + (k - 0.5) * RES
			local d = math.sqrt((x - sky.center.X) ^ 2 + (z - sky.center.Y) ^ 2) / sky.radius
			d *= 1 + 0.08 * WorldShape.noise(x, z, 80, 31)
			if d < 1 then
				local top = sky.top + 5 * WorldShape.noise(x, z, 60, 32) - 8 * d * d
				local bottom = top - sky.thickness * (1 - d * d) ^ 0.7 - 14 * math.abs(WorldShape.noise(x, z, 30, 33)) - 4
				local surface = d > 0.82 and cloud or grass
				for j = 1, layers do
					local y0 = yBase + (j - 1) * RES
					local above = (top - y0) / RES
					local below = (y0 + RES - bottom) / RES
					local fill = math.min(above, below, 1)
					if fill > 0 then
						matX[j][k] = (top - y0 > RES * 2) and under or surface
						occX[j][k] = fill
					end
				end
			end
		end
		matGrid[i], occGrid[i] = matX, occX
	end
	local low = Vector3.new(x0, yBase, z0)
	terrain:WriteVoxels(Region3.new(low, low + Vector3.new(size * RES, layers * RES, size * RES)), RES, matGrid, occGrid)
end

-- The cave: a tunnel from the Spindle's west foot into a crystal cavern under the mountain.
local function carveCave(terrain)
	local cave = Map.Cave
	local points = { cave.mouth }
	for _, p in cave.path do
		table.insert(points, p)
	end
	table.insert(points, cave.chamber.center)
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local steps = math.ceil((b - a).Magnitude / 6)
		for s = 0, steps do
			terrain:FillBall(a:Lerp(b, s / steps), 12, AIR)
		end
	end
	local c = cave.chamber
	terrain:FillBall(c.center, c.radius * 0.7, AIR)
	for _, offset in { Vector3.new(30, -6, 18), Vector3.new(-26, -4, -22), Vector3.new(10, 8, -30), Vector3.new(-12, -10, 28) } do
		terrain:FillBall(c.center + offset, c.radius * 0.5, AIR)
	end
	-- A flat cave floor to walk and haul on.
	terrain:FillBlock(CFrame.new(c.center - Vector3.new(0, c.radius * 0.45, 0)), Vector3.new(c.radius * 1.6, 8, c.radius * 1.6), material("Slate"))
end

-- True when this place already holds the current map (baked in Studio or written earlier this session). Checks a
-- voxel too: Meadow's own generator clears all terrain when its version changes.
function WorldTerrain.isBuilt()
	local terrain = Workspace.Terrain
	if terrain:GetAttribute("WorldMapVersion") ~= Map.Version then
		return false
	end
	local probe = Map.Flat[1] -- the Homestead plaza
	local mid = (probe.min + probe.max) / 2
	local y = probe.height - 2
	local region = Region3.new(Vector3.new(mid.X, y - 2, mid.Y), Vector3.new(mid.X + 4, y + 2, mid.Y + 4)):ExpandToGrid(RES)
	local ok, result = pcall(function()
		return terrain:ReadVoxels(region, RES)
	end)
	if not ok then
		return false
	end
	local m = result[1] and result[1][1] and result[1][1][1]
	return m ~= nil and m ~= AIR
end

-- Writes the whole map. Yields between chunks while the game runs so the server never freezes.
-- onProgress(done, total) is called after each chunk.
function WorldTerrain.generate(onProgress)
	local terrain = Workspace.Terrain
	local started = os.clock()
	setColors(terrain)

	local chunks = {}
	local min, max = Map.Bounds.min, Map.Bounds.max
	local span = CHUNK * RES
	for x0 = min.X, max.X - span, span do
		for z0 = min.Y, max.Y - span, span do
			-- Meadow's 4 x 4 chunks are its own (MeadowTerrain.luau).
			local inside = x0 >= -HALF and x0 + span <= HALF and z0 >= -HALF and z0 + span <= HALF
			if not inside then
				table.insert(chunks, { x0, z0 })
			end
		end
	end
	-- Nearest Meadow first, so the land around the spawn exists right away.
	table.sort(chunks, function(a, b)
		return (a[1] + span / 2) ^ 2 + (a[2] + span / 2) ^ 2 < (b[1] + span / 2) ^ 2 + (b[2] + span / 2) ^ 2
	end)

	for i, chunk in chunks do
		writeChunk(terrain, chunk[1], chunk[2])
		if onProgress then
			onProgress(i, #chunks)
		end
		if RunService:IsRunning() then
			task.wait()
		end
	end
	writeSkyIsland(terrain)
	carveCave(terrain)

	terrain:SetAttribute("WorldMapVersion", Map.Version)
	built = true
	print(("[Needlewood] Stitched Isles terrain written in %.1fs (%d chunks)"):format(os.clock() - started, #chunks))
end

-- Builds the map unless this place already has the current version.
function WorldTerrain.ensure(onProgress)
	if WorldTerrain.isBuilt() then
		setColors(Workspace.Terrain)
		built = true
		return
	end
	WorldTerrain.generate(onProgress)
end

function WorldTerrain.isReady()
	return built
end

-- The real ground under a point (terrain surface), falling back to the formula.
function WorldTerrain.groundAt(x, z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { Workspace.Terrain }
	params.IgnoreWater = true
	local hit = Workspace:Raycast(Vector3.new(x, Map.Top + 20, z), Vector3.new(0, -(Map.Top + 80), 0), params)
	if hit then
		return hit.Position.Y, hit.Normal, hit.Material
	end
	return WorldShape.heightAt(x, z), Vector3.yAxis, nil
end

return WorldTerrain
