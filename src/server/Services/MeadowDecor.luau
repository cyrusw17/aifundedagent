--!nonstrict
-- Everything standing on the Meadow terrain: hay bales scattered over the whole biome (never right up against a
-- building or on a road), LT2-style trees in groves, rocks, a fence along the north road, signposts, closed gates
-- where the roads leave the map, and walls at the map edge. Placement uses a fixed seed, so every server looks alike.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Meadow = require(Shared.Config.Meadow)
local Rustic = require(Shared.Config.Rustic)
local WorldLabel = require(Shared.WorldLabel)
local MeadowTerrain = require(script.Parent.MeadowTerrain)
local Bales = require(script.Parent.Bales)

local MeadowDecor = {}

local function part(parent, name, size, cframe, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

local function rectDistance(x, z, min, max)
	local dx = math.max(min.X - x, 0, x - max.X)
	local dz = math.max(min.Y - z, 0, z - max.Y)
	return math.sqrt(dx * dx + dz * dz)
end

-- True when nothing should be scattered here: near a building, on a road, in the pond, or out on the edge hills.
function MeadowDecor.isClear(x, z, margin)
	if math.abs(x) > Meadow.EdgeStart or math.abs(z) > Meadow.EdgeStart then
		return false
	end
	for _, rect in Meadow.KeepClear do
		if rectDistance(x, z, rect.min, rect.max) < margin then
			return false
		end
	end
	if MeadowTerrain.roadDistance(x, z) < Meadow.RoadMargin then
		return false
	end
	if (Vector2.new(x, z) - Meadow.Pond.center).Magnitude < Meadow.Pond.radius + 12 then
		return false
	end
	return true
end

-- A tree in the Lumber Tycoon 2 look: a cylinder trunk, two short branches, and boxy leaf clumps.
local function tree(parent, ground, scale, rng)
	local model = Instance.new("Model")
	model.Name = "Tree"
	local turn = CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local base = CFrame.new(ground - Vector3.new(0, 1, 0)) * turn
	local height = rng:NextNumber(10, 14) * scale
	local thick = rng:NextNumber(1.4, 1.9) * scale
	part(model, "Trunk", Vector3.new(height, thick, thick), base * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), Rustic.Bark, Enum.Material.Wood, Enum.PartType.Cylinder)
	for _, side in { -1, 1 } do
		local length = height * 0.35
		local branch = base
			* CFrame.new(0, height * rng:NextNumber(0.55, 0.7), 0)
			* CFrame.Angles(0, rng:NextNumber(0, math.pi), side * math.rad(40))
			* CFrame.new(0, length / 2, 0)
		local b = part(model, "Branch", Vector3.new(length, thick * 0.55, thick * 0.55), branch * CFrame.Angles(0, 0, math.pi / 2), Rustic.Bark, Enum.Material.Wood, Enum.PartType.Cylinder)
		b.CanCollide = false
	end
	local leafColors = { Rustic.Leaves, Rustic.LeavesDark, Rustic.LeavesDry }
	for i = 1, rng:NextInteger(3, 4) do
		local size = Vector3.new(rng:NextNumber(6, 9), rng:NextNumber(4, 6), rng:NextNumber(6, 9)) * scale
		local offset = Vector3.new(rng:NextNumber(-2.5, 2.5), height + rng:NextNumber(-1.5, 2.5) + (i == 1 and 0 or 1), rng:NextNumber(-2.5, 2.5)) * Vector3.new(scale, 1, scale)
		local leaf = part(
			model,
			"Leaves",
			size,
			base * CFrame.new(offset) * CFrame.Angles(rng:NextNumber(-0.15, 0.15), rng:NextNumber(0, math.pi), rng:NextNumber(-0.15, 0.15)),
			leafColors[rng:NextInteger(1, i == 1 and 2 or 3)],
			Enum.Material.Grass
		)
		leaf.CanCollide = false
	end
	model.PrimaryPart = model.Trunk
	model.Parent = parent
	return model
end

local function rock(parent, ground, rng)
	local size = Vector3.new(rng:NextNumber(2, 7), rng:NextNumber(1.5, 4), rng:NextNumber(2, 6))
	local colors = { Rustic.Stone, Rustic.StoneDark, Rustic.Rock }
	local cf = CFrame.new(ground + Vector3.new(0, size.Y * 0.2, 0))
		* CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, math.pi * 2), rng:NextNumber(-0.3, 0.3))
	part(parent, "Rock", size, cf, colors[rng:NextInteger(1, 3)], Enum.Material.Slate)
end

-- A wooden board on a post. facing is the way the readable front looks. Arrows only make sense from the front, so
-- the back is blank unless bothSides is set.
local function signpost(parent, position, facing, text, width, bothSides)
	width = width or 9
	local model = Instance.new("Model")
	model.Name = "Signpost"
	local y = MeadowTerrain.groundAt(position.X, position.Y)
	local base = CFrame.lookAt(Vector3.new(position.X, y, position.Y), Vector3.new(position.X + facing.X, y, position.Y + facing.Y))
	part(model, "Post", Vector3.new(0.6, 7, 0.6), base * CFrame.new(0, 3, 0.4), Rustic.WoodDark, Enum.Material.Wood)
	local board = part(model, "Board", Vector3.new(width, 3.6, 0.4), base * CFrame.new(0, 6.2, 0), Rustic.Wood, Enum.Material.WoodPlanks)
	WorldLabel.surface(board, text, bothSides and { Enum.NormalId.Front, Enum.NormalId.Back } or { Enum.NormalId.Front })
	model.Parent = parent
	return model
end

-- Posts every 8 studs with two rails, following the ground.
local function fence(parent, from, to)
	local model = Instance.new("Model")
	model.Name = "Fence"
	local length = (to - from).Magnitude
	local count = math.max(1, math.floor(length / 8))
	local previous = nil
	for i = 0, count do
		local p = from:Lerp(to, i / count)
		local y = MeadowTerrain.groundAt(p.X, p.Y)
		local top = Vector3.new(p.X, y, p.Y)
		part(model, "Post", Vector3.new(0.6, 4, 0.6), CFrame.new(top + Vector3.new(0, 1.6, 0)), Rustic.WoodDark, Enum.Material.Wood)
		if previous then
			for _, h in { 1.4, 2.8 } do
				local a, b = previous + Vector3.new(0, h, 0), top + Vector3.new(0, h, 0)
				part(model, "Rail", Vector3.new(0.3, 0.5, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), Rustic.Wood, Enum.Material.WoodPlanks)
			end
		end
		previous = top
	end
	model.Parent = parent
end

-- A closed gate across a road where it leaves the map, with an invisible wall so nobody wanders off.
local function gate(parent, def)
	local model = Instance.new("Model")
	model.Name = "ClosedGate"
	local y = MeadowTerrain.groundAt(def.at.X, def.at.Y)
	local base = CFrame.lookAt(Vector3.new(def.at.X, y, def.at.Y), Vector3.new(def.at.X + def.facing.X, y, def.at.Y + def.facing.Y))
	local span = Meadow.RoadWidth + 4
	for _, side in { -1, 1 } do
		part(model, "GatePost", Vector3.new(1, 6, 1), base * CFrame.new(side * span / 2, 2.5, 0), Rustic.WoodDark, Enum.Material.Wood)
	end
	for _, h in { 1.6, 3.4 } do
		part(model, "Bar", Vector3.new(span, 0.6, 0.4), base * CFrame.new(0, h, 0), Rustic.PaintCream, Enum.Material.WoodPlanks)
	end
	local wall = part(model, "Wall", Vector3.new(span + 30, 60, 2), base * CFrame.new(0, 28, 2), Color3.new(), Enum.Material.SmoothPlastic)
	wall.Transparency = 1
	model.Parent = parent
	signpost(parent, Vector2.new(def.at.X, def.at.Y) + def.facing * 3, def.facing, def.text, 11, true)
end

local function edgeWalls(parent)
	local h = Meadow.HalfSize - 6
	for _, def in {
		{ Vector3.new(h, 0, 0), Vector3.new(2, 300, h * 2) },
		{ Vector3.new(-h, 0, 0), Vector3.new(2, 300, h * 2) },
		{ Vector3.new(0, 0, h), Vector3.new(h * 2, 300, 2) },
		{ Vector3.new(0, 0, -h), Vector3.new(h * 2, 300, 2) },
	} do
		local wall = part(parent, "EdgeWall", def[2], CFrame.new(def[1] + Vector3.new(0, 100, 0)), Color3.new(), Enum.Material.SmoothPlastic)
		wall.Transparency = 1
		wall.CanQuery = false
	end
end

local function placeTrees(parent, rng, taken)
	local placed = 0
	local tries = 0
	while placed < Meadow.TreeCount and tries < Meadow.TreeCount * 40 do
		tries += 1
		local x = rng:NextNumber(-Meadow.HalfSize + 40, Meadow.HalfSize - 40)
		local z = rng:NextNumber(-Meadow.HalfSize + 40, Meadow.HalfSize - 40)
		-- Trees grow in groves: only where this slow noise is high, plus the odd lone tree.
		local grove = math.noise(x / 160 + Meadow.Seed, z / 160 - Meadow.Seed, 3.3)
		if grove < 0.12 and rng:NextNumber() > 0.08 then
			continue
		end
		local onEdge = math.abs(x) > Meadow.EdgeStart or math.abs(z) > Meadow.EdgeStart
		if not onEdge and not MeadowDecor.isClear(x, z, Meadow.BuildingMargin + 6) then
			continue
		end
		if MeadowTerrain.roadDistance(x, z) < Meadow.RoadMargin + 6 then
			continue
		end
		local crowded = false
		for _, other in taken do
			if (other - Vector2.new(x, z)).Magnitude < 12 then
				crowded = true
				break
			end
		end
		if crowded then
			continue
		end
		local y, normal = MeadowTerrain.groundAt(x, z)
		if normal.Y < 0.75 then
			continue
		end
		tree(parent, Vector3.new(x, y, z), rng:NextNumber(0.85, 1.3), rng)
		table.insert(taken, Vector2.new(x, z))
		placed += 1
	end
end

local function placeRocks(parent, rng, taken)
	for _ = 1, Meadow.RockCount do
		local x = rng:NextNumber(-Meadow.HalfSize + 30, Meadow.HalfSize - 30)
		local z = rng:NextNumber(-Meadow.HalfSize + 30, Meadow.HalfSize - 30)
		local onEdge = math.abs(x) > Meadow.EdgeStart or math.abs(z) > Meadow.EdgeStart
		if (onEdge or MeadowDecor.isClear(x, z, Meadow.BuildingMargin)) and MeadowTerrain.roadDistance(x, z) > Meadow.RoadMargin then
			local y = MeadowTerrain.groundAt(x, z)
			rock(parent, Vector3.new(x, y, z), rng)
			table.insert(taken, Vector2.new(x, z))
		end
	end
end

-- Hay bales all over the meadow, in small groups, away from buildings, roads, trees and the pond.
local function scatterBales(rng, taken)
	local cell = Meadow.BaleCell
	local count = 0
	local half = Meadow.HalfSize
	for cx = -half, half - cell, cell do
		for cz = -half, half - cell, cell do
			if rng:NextNumber() >= Meadow.BaleChance then
				continue
			end
			local center = Vector2.new(cx + rng:NextNumber(6, cell - 6), cz + rng:NextNumber(6, cell - 6))
			local n = rng:NextInteger(Meadow.BalesPerGroup[1], Meadow.BalesPerGroup[2])
			local group = {}
			for _ = 1, n do
				local spot = center + Vector2.new(rng:NextNumber(-6, 6), rng:NextNumber(-6, 6))
				if not MeadowDecor.isClear(spot.X, spot.Y, Meadow.BuildingMargin) then
					continue
				end
				local crowded = false
				for _, other in taken do
					if (other - spot).Magnitude < 5 then
						crowded = true
						break
					end
				end
				for _, other in group do
					if (other - spot).Magnitude < 5 then
						crowded = true
						break
					end
				end
				if crowded then
					continue
				end
				local y, normal, material = MeadowTerrain.groundAt(spot.X, spot.Y)
				if y > Meadow.MaxScatterHeight or normal.Y < 0.85 or material == Enum.Material.Water then
					continue
				end
				-- Sink it a little so the downhill edge does not float on a slope.
				Bales.spawn(Vector3.new(spot.X, y - 0.35, spot.Y), true)
				table.insert(group, spot)
				count += 1
			end
			for _, spot in group do
				table.insert(taken, spot)
			end
		end
	end
	return count
end

function MeadowDecor.build(worldFolder)
	local folder = Instance.new("Folder")
	folder.Name = "Meadow"
	folder.Parent = worldFolder
	local rng = Random.new(Meadow.Seed)
	local taken = {}

	local trees = Instance.new("Folder")
	trees.Name = "Trees"
	trees.Parent = folder
	placeTrees(trees, rng, taken)

	local rocks = Instance.new("Folder")
	rocks.Name = "Rocks"
	rocks.Parent = folder
	placeRocks(rocks, rng, taken)

	-- A fence lines both sides of the north road as it leaves camp.
	for _, side in { -1, 1 } do
		fence(folder, Vector2.new(side * 11, -46), Vector2.new(side * 11, -190))
	end

	-- Signposts at base camp and in front of the dealer.
	signpost(folder, Vector2.new(-14, 6), Vector2.new(0, 1), "< TRUCK DEALER\nSELL HAY >", 10)
	signpost(folder, Vector2.new(2, 40), Vector2.new(0, -1), "LAND OFFICE\nPLOTS FOR SALE", 11, true)
	signpost(folder, Vector2.new(-112, 36), Vector2.new(1, 0), "HOMESTEAD MOTORS\nTRUCKS FOR SALE", 11, true)
	signpost(folder, Vector2.new(10, -38), Vector2.new(0, 1), "BASE CAMP\n^ HOMESTEAD VALLEY (soon)", 11)
	signpost(folder, Vector2.new(130, 36), Vector2.new(-1, 0), "< STARTER BASE\nPINE FOREST (soon) >", 11)

	for _, def in Meadow.Gates do
		gate(folder, def)
	end
	edgeWalls(folder)

	local decor = #taken
	local bales = scatterBales(rng, taken)
	print(("[Needlewood] Meadow: %d trees and rocks, %d hay bales scattered"):format(decor, bales))
end

return MeadowDecor
