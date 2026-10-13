--!nonstrict
-- Conveyor belts made of square tiles on a grid. Every tile is TileSize x TileSize studs and points one of four ways.
-- A tile's belt is an anchored part with a velocity, so anything resting on it slides along. Rails are added
-- after a line is laid, so they go only where nothing feeds in from the side.
--
-- Belts run on two levels: level 0 (belt top at Factory.BeltTop) and level 1, Factory.LevelRise higher, high enough
-- for a loaded belt to pass underneath. A ramp (two cells long) carries loads from one level to the other, so one
-- line can bridge over another. Machines sit on level 0.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Factory = require(ReplicatedStorage.Shared.Config.Factory)
local Skins = require(script.Parent.Skins)

local Conveyors = {}

local T = Factory.TileSize
local RAIL = 0.3
local RAIL_HEIGHT = 1.2
-- Rustic palette (blender/lib/style.py): weathered wood frame, dark rubber belt, plain weathered metal rails and legs.
local FRAME = Color3.fromRGB(179, 153, 115)
local BELT = Color3.fromRGB(41, 33, 26)
local RAIL_COLOR = Color3.fromRGB(128, 117, 105)
local LEG = Color3.fromRGB(107, 94, 84)

Conveyors.TILE = T
Conveyors.Dirs = {
	N = Vector3.new(0, 0, -1),
	S = Vector3.new(0, 0, 1),
	E = Vector3.new(1, 0, 0),
	W = Vector3.new(-1, 0, 0),
}

local SLICK = PhysicalProperties.new(0.7, 0, 0, 100, 1) -- rails: no friction, so loads slide along them
local GRIP = PhysicalProperties.new(0.7, 1.5, 0, 100, 1) -- belt: grips the load

local function key(gx, gz, level)
	if level and level > 0 then
		return ("%d,%d,%d"):format(gx, gz, level)
	end
	return gx .. "," .. gz
end

local function topAt(level)
	return Factory.BeltTop + (level or 0) * Factory.LevelRise
end
Conveyors.topAt = topAt

local function part(parent, name, size, cframe, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- A grid has an origin (the corner of cell 0,0 on the ground) and remembers every tile laid on it.
function Conveyors.newGrid(parent, origin)
	local folder = Instance.new("Folder")
	folder.Name = "Conveyors"
	folder.Parent = parent
	return { origin = origin, folder = folder, tiles = {} }
end

-- Ground point at the middle of a cell.
function Conveyors.cellCenter(grid, gx, gz)
	return grid.origin + Vector3.new((gx + 0.5) * T, 0, (gz + 0.5) * T)
end

-- Ground-level CFrame at the middle of a cell, facing dir. Machines.luau places its pieces with this.
function Conveyors.frame(grid, gx, gz, dir)
	local ground = Conveyors.cellCenter(grid, gx, gz)
	return CFrame.lookAt(ground, ground + Conveyors.Dirs[dir])
end

local function makeBelt(model, size, cframe, velocity)
	local belt = part(model, "Belt", size, cframe, BELT)
	belt.CustomPhysicalProperties = GRIP
	belt.AssemblyLinearVelocity = velocity
	belt:SetAttribute("Speed", Factory.BeltSpeed)
	CollectionService:AddTag(belt, "ConveyorBelt")
	return belt
end

local function legs(model, ground, height, name)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			part(
				model,
				name,
				Vector3.new(0.4, height, 0.4),
				CFrame.new(ground + Vector3.new(sx * (T / 2 - 0.6), height / 2, sz * (T / 2 - 0.6))),
				LEG,
				Enum.Material.Metal
			)
		end
	end
end

-- Lays one tile. dir is "N", "S", "E" or "W". openBack leaves the back end without a rail (for a loading dock).
-- level is 0 (the default) or 1 for a raised belt.
function Conveyors.place(grid, gx, gz, dir, openBack, level)
	level = level or 0
	local d = Conveyors.Dirs[dir]
	local ground = Conveyors.cellCenter(grid, gx, gz)
	local top = ground + Vector3.new(0, topAt(level), 0)
	local facing = CFrame.lookAt(top, top + d)

	local model = Instance.new("Model")
	model.Name = level > 0 and ("Conveyor_%d_%d_L%d"):format(gx, gz, level) or ("Conveyor_%d_%d"):format(gx, gz)

	local belt = makeBelt(model, Vector3.new(T, 0.4, T), facing * CFrame.new(0, -0.2, 0), d * Factory.BeltSpeed)
	part(model, "Frame", Vector3.new(T, 0.6, T - 0.2), facing * CFrame.new(0, -0.7, 0), FRAME, Enum.Material.WoodPlanks)
	if level == 0 then
		legs(model, ground, Factory.BeltTop - 1, "Leg")
	end -- raised tiles get legs in finish(), only where no belt runs underneath

	model.PrimaryPart = belt
	model.Parent = grid.folder
	local tile = { gx = gx, gz = gz, dir = dir, d = d, model = model, openBack = openBack, outs = { d }, level = level }
	grid.tiles[key(gx, gz, level)] = tile
	return belt
end

-- A ramp: two cells long, from (gx, gz) forward in dir. up = true climbs from level 0 to level 1, false comes down.
-- It takes both cells on both levels (nothing else fits under its slope). Returns the belt.
function Conveyors.ramp(grid, gx, gz, dir, up)
	local d = Conveyors.Dirs[dir]
	local inLevel, outLevel = (up and 0 or 1), (up and 1 or 0)
	local a = Conveyors.cellCenter(grid, gx, gz) - d * (T / 2) -- back edge
	local b = Conveyors.cellCenter(grid, gx + d.X, gz + d.Z) + d * (T / 2) -- front edge
	local from = a + Vector3.new(0, topAt(inLevel), 0)
	local to = b + Vector3.new(0, topAt(outLevel), 0)
	local slope = CFrame.lookAt(from, to)
	local length = (to - from).Magnitude

	local model = Instance.new("Model")
	model.Name = ("ConveyorRamp_%d_%d"):format(gx, gz)
	local mid = slope * CFrame.new(0, 0, -length / 2)
	local belt = makeBelt(model, Vector3.new(T, 0.4, length), mid * CFrame.new(0, -0.2, 0), slope.LookVector * Factory.BeltSpeed)
	part(model, "Frame", Vector3.new(T, 0.6, length), mid * CFrame.new(0, -0.7, 0), FRAME, Enum.Material.WoodPlanks)
	-- Cleats on a ramp keep loads from sliding back.
	belt.CustomPhysicalProperties = PhysicalProperties.new(0.7, 2, 0, 100, 1)
	for _, side in { -1, 1 } do
		local rail = part(model, "RampRail", Vector3.new(RAIL, RAIL_HEIGHT, length), mid * CFrame.new(side * (T / 2 - RAIL / 2), RAIL_HEIGHT / 2, 0), RAIL_COLOR, Enum.Material.Metal)
		rail.CustomPhysicalProperties = SLICK
	end
	for _, at in { a + d * 0.8, b - d * 0.8 } do
		-- The belt's top above this point, less the belt and frame under it.
		local along = (at - a):Dot(d) / (b - a):Dot(d)
		local height = math.max(0.5, topAt(inLevel) + (topAt(outLevel) - topAt(inLevel)) * along - 1.1)
		for _, sx in { -1, 1 } do
			local side = Vector3.new(d.Z, 0, -d.X) * sx * (T / 2 - 0.6)
			part(model, "Leg", Vector3.new(0.4, height, 0.4), CFrame.new(at + side + Vector3.new(0, height / 2, 0)), LEG, Enum.Material.Metal)
		end
	end

	model.PrimaryPart = belt
	model.Parent = grid.folder
	local tile = { gx = gx, gz = gz, dir = dir, d = d, model = model, outs = { d }, kind = "ramp", level = inLevel, up = up }
	tile.cells = { { gx, gz }, { gx + d.X, gz + d.Z } }
	-- The back cell is where loads come in (at inLevel), the front cell where they leave (at outLevel). Both levels of
	-- both cells are taken.
	for _, cell in tile.cells do
		for _, level in { 0, 1 } do
			grid.tiles[key(cell[1], cell[2], level)] = tile
		end
	end
	tile.inAt = { gx = gx, gz = gz, level = inLevel }
	tile.outAt = { gx = gx + d.X, gz = gz + d.Z, level = outLevel }
	return belt
end

-- The tile laid at a cell (on level 0 unless given), or nil.
function Conveyors.tileAt(grid, gx, gz, level)
	return grid.tiles[key(gx, gz, level)]
end

-- Takes a tile (or ramp) off the grid and destroys it. finish() again afterwards to redo the rails.
function Conveyors.remove(grid, tile)
	for k, t in grid.tiles do
		if t == tile then
			grid.tiles[k] = nil
		end
	end
	tile.model:Destroy()
end

-- The directions to a tile's left and right, seen facing its flow.
function Conveyors.sides(d)
	return Vector3.new(d.Z, 0, -d.X), Vector3.new(-d.Z, 0, d.X)
end

-- Turns a laid tile into a splitter: loads come in from behind and leave through its left and right sides (moved by
-- Machines.splitter), so finish() leaves both sides open and puts a rail across the front.
function Conveyors.makeSplitter(grid, gx, gz)
	local tile = grid.tiles[key(gx, gz)]
	tile.kind = "splitter"
	tile.outs = { Conveyors.sides(tile.d) }
	return tile
end

-- A rail along one edge of a tile whose belt top is at `top` (a point above the cell's middle).
local function addRail(tile, side, top)
	local center = top + side * (T / 2 - RAIL / 2) + Vector3.new(0, RAIL_HEIGHT / 2, 0)
	local size = side.X ~= 0 and Vector3.new(RAIL, RAIL_HEIGHT, T) or Vector3.new(T, RAIL_HEIGHT, RAIL)
	local rail = part(tile.model, "Rail", size, CFrame.new(center), RAIL_COLOR, Enum.Material.Metal)
	rail.CustomPhysicalProperties = SLICK
end

-- Does the tile n (seen from a tile at `level`, on its `side`) carry loads into that tile?
local function feeds(n, side, level, gx, gz)
	if not n then
		return false
	end
	if n.kind == "ramp" then
		-- A ramp only hands loads on from its front cell, at its top level, straight ahead.
		local o = n.outAt
		return o.level == level and o.gx + n.d.X == gx and o.gz + n.d.Z == gz and (n.d + side).Magnitude < 0.01
	end
	if (n.level or 0) ~= level then
		return false
	end
	for _, out in n.outs do
		if (out + side).Magnitude < 0.01 then
			return true
		end
	end
	return false
end

-- Clears what finish() added last time (rails, raised legs, meshes), so finish() can run again after an edit.
local function clearFinish(tile)
	for _, child in tile.model:GetChildren() do
		if child.Name == "Rail" or child.Name == "RaisedLeg" then
			child:Destroy()
		end
	end
	local frame = tile.model:FindFirstChild("Frame")
	for _, child in frame and frame:GetChildren() or {} do
		if child:IsA("Model") then
			child:Destroy()
		end
	end
end

-- Adds rails once the whole line is laid, and again after any edit. A side gets a rail unless a tile there feeds into
-- this one. The back gets a rail unless something feeds in from behind. The front is left open so loads move on.
-- Tiles on level 0 also get their Blender mesh when it was imported: conveyor_straight when nothing feeds in from a
-- side, merger when both sides feed in, splitter on a splitter. Corners, T-joins, raised belts and ramps keep the
-- part-built look.
function Conveyors.finish(grid)
	local done = {}
	for _, tile in grid.tiles do
		if done[tile] then
			continue
		end
		done[tile] = true
		clearFinish(tile)
		local level = tile.level or 0
		local ground = Conveyors.cellCenter(grid, tile.gx, tile.gz)

		if tile.kind == "ramp" then
			-- Only the back can need a rail; the sides have their own sloped rails.
			local i = tile.inAt
			local behind = grid.tiles[key(i.gx - tile.d.X, i.gz - tile.d.Z, i.level)]
			if not feeds(behind, -tile.d, i.level, i.gx, i.gz) then
				addRail(tile, -tile.d, ground + Vector3.new(0, topAt(i.level), 0))
			end
			continue
		end

		local top = ground + Vector3.new(0, topAt(level), 0)
		local left, right = Conveyors.sides(tile.d)
		local sides = { left, right }
		if not tile.openBack then
			table.insert(sides, -tile.d)
		end
		local fed = 0
		for i, side in sides do
			local nx, nz = tile.gx + math.round(side.X), tile.gz + math.round(side.Z)
			local n = grid.tiles[key(nx, nz, level)]
			if tile.kind == "splitter" and i <= 2 then
				-- A splitter's sides are its ways out: open wherever there is a tile to take the load.
				if not n then
					addRail(tile, side, top)
				end
			elseif not feeds(n, side, level, tile.gx, tile.gz) then
				addRail(tile, side, top)
			elseif i <= 2 then
				fed += 1
			end
		end
		if tile.kind == "splitter" then
			addRail(tile, tile.d, top)
		end

		if level > 0 then
			if not grid.tiles[key(tile.gx, tile.gz, 0)] then
				legs(tile.model, ground, topAt(level) - 1, "RaisedLeg")
			end
			continue
		end
		-- The meshes' belts run along their own X axis, in at -X and out at +X.
		local frame = Conveyors.frame(grid, tile.gx, tile.gz, tile.dir)
		local turn = CFrame.Angles(0, math.pi / 2, 0)
		if tile.kind == "splitter" then
			Skins.dress("splitter", tile.model.Frame, tile.model, frame, turn)
		elseif fed == 2 then
			Skins.dress("merger", tile.model.Frame, tile.model, frame, turn)
		elseif fed == 0 then
			Skins.dress("conveyor_straight", tile.model.Frame, tile.model, frame, turn)
		end
	end
end

-- Lays a straight run of tiles from (gx, gz) for count cells in dir, on level (default 0).
function Conveyors.run(grid, gx, gz, dir, count, level)
	local d = Conveyors.Dirs[dir]
	for i = 0, count - 1 do
		Conveyors.place(grid, gx + d.X * i, gz + d.Z * i, dir, nil, level)
	end
end

return Conveyors
